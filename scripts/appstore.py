#!/usr/bin/env python3
"""App Store Connect API helper for BSHEEL's two publish branches.

Commands:
    next-build   <bundle-id>                  next unused build number (asks Apple)
    live-version <bundle-id>                  highest version string already on the App Store
    check-version <bundle-id> <version>       fail unless <version> is higher than what is live
    distribute   <bundle-id> <build-number>   wait for that build, hand it to the TestFlight groups
    submit       <bundle-id> <version> <build-number>   create the App Store version and submit it

Credentials come from the environment (ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8) in CI, or from
the macOS Keychain locally. Only the Python standard library and `openssl` are used.

Nothing here writes a secret to disk except a 0600 temp file that exists for the duration of
one signature and is removed in a `finally`.
"""

import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
KEYCHAIN_SERVICE = "BSHEEL-ASC"
PLATFORM = "IOS"


def die(message, code=1):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(code)


# --------------------------------------------------------------------------- credentials

def load_credentials():
    env = {
        "keyId": os.environ.get("ASC_KEY_ID", "").strip(),
        "issuerId": os.environ.get("ASC_ISSUER_ID", "").strip(),
        "p8": os.environ.get("ASC_KEY_P8", ""),
    }
    if all(env.values()):
        return env
    try:
        raw = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        return json.loads(raw)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        die("no App Store Connect key found. Set ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8, "
            f"or store one in the Keychain as '{KEYCHAIN_SERVICE}'.")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw_signature(der: bytes) -> bytes:
    """ES256 wants a fixed 64-byte r||s; openssl emits a DER SEQUENCE of two INTEGERs."""
    if not der or der[0] != 0x30:
        raise ValueError("signature is not a DER sequence")
    index = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F) - 1

    def read_int(i):
        if der[i] != 0x02:
            raise ValueError("expected a DER integer")
        length = der[i + 1]
        return der[i + 2:i + 2 + length].lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length

    r, index = read_int(index)
    s, _ = read_int(index)
    return r + s


def make_token(creds) -> str:
    header = {"alg": "ES256", "kid": creds["keyId"], "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": creds["issuerId"], "iat": now, "exp": now + 15 * 60,
               "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"

    handle, key_path = tempfile.mkstemp(suffix=".p8")
    try:
        os.write(handle, creds["p8"].encode())
        os.close(handle)
        os.chmod(key_path, 0o600)
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                             input=signing_input.encode(), check=True, capture_output=True).stdout
    finally:
        try:
            os.remove(key_path)
        except FileNotFoundError:
            pass
    return f"{signing_input}.{b64url(der_to_raw_signature(der))}"


# --------------------------------------------------------------------------- transport

_TOKEN = {"value": None, "minted": 0.0}


def auth():
    """A bearer token that is always valid, re-minted before it can expire.

    Apple rejects a JWT older than 20 minutes. `distribute` and `submit` legitimately wait up to
    half an hour for a build to finish processing, so a token minted once at startup dies
    mid-wait and every call after that fails with "Authentication credentials are missing or
    invalid" — after the build has already uploaded and the expensive work is done.

    The token passed around by the commands is ignored in favour of this; signing a fresh one
    costs a single openssl call.
    """
    if _TOKEN["value"] is None or time.time() - _TOKEN["minted"] > 10 * 60:
        _TOKEN["value"] = make_token(load_credentials())
        _TOKEN["minted"] = time.time()
    return _TOKEN["value"]


def _request(method, path, token=None, payload=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Authorization": f"Bearer {auth()}"}
    if data:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
            return True, (json.loads(body) if body else {})
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            return False, json.loads(raw)
        except json.JSONDecodeError:
            return False, {"errors": [{"detail": raw}]}
    except urllib.error.URLError as error:
        die(f"could not reach App Store Connect: {error.reason}")


def get(path, token, params=None):
    if params:
        pairs = "&".join(f"{k}={urllib.request.quote(str(v), safe='')}" for k, v in params.items())
        path = f"{path}?{pairs}"
    ok, body = _request("GET", path, token)
    if not ok:
        die(f"GET {path} failed: {describe(body)}")
    return body


def post(path, token, payload):
    return _request("POST", path, token, payload)


def patch(path, token, payload):
    return _request("PATCH", path, token, payload)


def paged(path, token, params=None):
    params = dict(params or {})
    params.setdefault("limit", 200)
    results, payload = [], get(path, token, params)
    while True:
        results.extend(payload.get("data", []))
        nxt = payload.get("links", {}).get("next")
        if not nxt:
            return results
        ok, payload = _request("GET", nxt, token)
        if not ok:
            return results


def describe(body):
    errors = body.get("errors", []) if isinstance(body, dict) else []
    if not errors:
        return str(body)
    return "; ".join(f"{e.get('title','')}: {e.get('detail','')}".strip(" :") for e in errors)


# --------------------------------------------------------------------------- helpers

def find_app(token, bundle_id):
    apps = get("/v1/apps", token, {"filter[bundleId]": bundle_id, "limit": 10}).get("data", [])
    exact = [a for a in apps if a["attributes"].get("bundleId") == bundle_id]
    if not exact:
        die(f"no app record for bundle id '{bundle_id}'")
    return exact[0]


def version_tuple(value):
    """'2.0.10' -> (2, 0, 10). Compared numerically, because '2.0.10' sorts before '2.0.9'."""
    parts = re.findall(r"\d+", value or "")
    return tuple(int(p) for p in parts) or (0,)


def live_version_string(token, app_id):
    """Highest version string Apple already knows about, in any state."""
    versions = paged(f"/v1/apps/{app_id}/appStoreVersions", token,
                     {"fields[appStoreVersions]": "versionString,appStoreState"})
    strings = [v["attributes"].get("versionString") for v in versions if v.get("attributes")]
    strings = [s for s in strings if s]
    return max(strings, key=version_tuple) if strings else None


def wait_for_build(token, app_id, expected, minutes=30):
    """Wait for the build WE just uploaded, by number.

    Asking for "the newest build" instead is a trap: seconds after an upload Apple has not
    registered it yet, so the caller silently operates on the previous build and reports
    success. That is worse than failing.
    """
    for attempt in range(minutes * 2):
        match = next((b for b in get("/v1/builds", token, {
            "filter[app]": app_id, "limit": 20, "sort": "-version",
            "fields[builds]": "version,processingState,usesNonExemptEncryption"}).get("data", [])
            if str(b["attributes"].get("version")) == str(expected)), None)
        if match is None:
            print(f"waiting for build {expected} to appear…", flush=True)
        else:
            state = match["attributes"].get("processingState")
            print(f"build {expected}: {state}", flush=True)
            if state == "VALID":
                return match
            if state in ("INVALID", "FAILED"):
                die(f"Apple rejected build {expected} ({state}). Check the team's email.")
        if attempt < minutes * 2 - 1:
            time.sleep(30)
    die(f"build {expected} never finished processing")


# --------------------------------------------------------------------------- commands

def cmd_next_build(token, args):
    app = find_app(token, args[0])
    numbers = []
    for build in get("/v1/builds", token, {"filter[app]": app["id"], "sort": "-version",
                                           "limit": 200, "fields[builds]": "version"}).get("data", []):
        try:
            numbers.append(int(build["attributes"]["version"]))
        except (KeyError, TypeError, ValueError):
            continue
    print((max(numbers) if numbers else 0) + 1)


def cmd_live_version(token, args):
    app = find_app(token, args[0])
    print(live_version_string(token, app["id"]) or "0.0.0")


def cmd_check_version(token, args):
    """Refuse to ship a version Apple will reject, before spending a build on it."""
    if len(args) < 2:
        die("usage: appstore.py check-version <bundle-id> <version>")
    bundle_id, proposed = args[0], args[1]
    app = find_app(token, bundle_id)
    live = live_version_string(token, app["id"])
    print(f"pubspec version: {proposed}")
    print(f"highest on App Store Connect: {live or '(none)'}")
    if live and version_tuple(proposed) <= version_tuple(live):
        die(f"version {proposed} is not higher than {live}. "
            f"Bump `version:` in apps/mobile_app/pubspec.yaml before pushing to publish-store.")
    print("ok: version is new")


def answer_export_compliance(token, build):
    """Answer Apple's encryption question so the build can actually reach testers.

    A build can be VALID and still sit in "Missing Compliance", invisible to every tester,
    until someone opens App Store Connect and answers "What type of encryption algorithms does
    your app implement?". Build 74 processed cleanly, this script reported success, and it
    reached nobody until the question was answered by hand.

    `false` is the same answer as "None of the algorithms mentioned above": the app uses only
    the standard encryption exempt from export regulations (HTTPS to Supabase and Firebase).
    Info.plist now declares ITSAppUsesNonExemptEncryption so Apple stops asking at all; this
    covers builds uploaded before that landed, and is a no-op once it is already answered.

    If BSHEEL ever adds its own cryptography, this answer stops being true and must change —
    it is a legal declaration, not a checkbox.
    """
    if build["attributes"].get("usesNonExemptEncryption") is not None:
        return
    ok, body = patch(f"/v1/builds/{build['id']}", token, {
        "data": {"type": "builds", "id": build["id"],
                 "attributes": {"usesNonExemptEncryption": False}}
    })
    if ok:
        print("answered Apple's export-compliance question (no non-exempt encryption)")
    else:
        print(f"could not answer export compliance: {describe(body)}\n"
              f"  The build will stay invisible to testers until it is answered in "
              f"App Store Connect.", file=sys.stderr)


def cmd_distribute(token, args):
    """Hand the build to every TestFlight group. Uploading is not distributing."""
    if len(args) < 2:
        die("usage: appstore.py distribute <bundle-id> <build-number>")
    app = find_app(token, args[0])
    build = wait_for_build(token, app["id"], args[1])
    answer_export_compliance(token, build)

    groups = paged(f"/v1/apps/{app['id']}/betaGroups", token)
    if not groups:
        print("no TestFlight groups exist yet — the build is uploaded but nobody is testing it")
        return
    for group in groups:
        attrs = group["attributes"]
        name = attrs.get("name")
        internal = attrs.get("isInternalGroup")
        all_builds = attrs.get("hasAccessToAllBuilds")

        # An internal group set to "all builds" receives every build the moment it finishes
        # processing, and Apple REFUSES a manual assignment: "Cannot add internal group to a
        # build." Trying anyway and printing the refusal as an error made a successful ship
        # look broken. Nothing to do here but say so.
        if internal and all_builds:
            print(f"build {args[1]} -> '{name}' (internal, automatic)")
            continue

        ok, body = post(f"/v1/betaGroups/{group['id']}/relationships/builds", token,
                        {"data": [{"type": "builds", "id": build["id"]}]})
        detail = describe(body).lower()
        if ok or "already" in detail:
            print(f"build {args[1]} -> '{name}'")
        elif not internal and "externally assignable" in detail:
            # External testers only ever see builds that have passed Beta App Review, which is
            # a separate submission from the App Store review this repo does not automate.
            print(f"'{name}' is EXTERNAL: build {args[1]} needs Beta App Review before those "
                  f"testers can install it. Internal testers already have it.")
        else:
            print(f"could not add build to '{name}': {describe(body)}", file=sys.stderr)


def cmd_submit(token, args):
    """Create the App Store version, attach the build, and submit it for review."""
    if len(args) < 3:
        die("usage: appstore.py submit <bundle-id> <version> <build-number>")
    bundle_id, version, build_number = args[0], args[1], args[2]
    app = find_app(token, bundle_id)
    app_id = app["id"]
    build = wait_for_build(token, app_id, build_number)
    # A build with an unanswered encryption question cannot be submitted for review either.
    answer_export_compliance(token, build)

    # 1. Reuse an editable version if one exists, otherwise create it. Creating a second one
    #    for the same version string is rejected, and re-running a failed ship must be safe.
    editable = next((v for v in paged(f"/v1/apps/{app_id}/appStoreVersions", token,
                                      {"fields[appStoreVersions]": "versionString,appStoreState"})
                     if v["attributes"].get("appStoreState") in EDITABLE_STATES), None)

    if editable and editable["attributes"].get("versionString") != version:
        die(f"App Store Connect already has an editable version "
            f"{editable['attributes'].get('versionString')} in state "
            f"{editable['attributes'].get('appStoreState')}. Finish or delete it before shipping {version}.")

    if editable:
        version_id = editable["id"]
        print(f"reusing existing editable version {version}")
    else:
        ok, body = post("/v1/appStoreVersions", token, {
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": PLATFORM,
                    "versionString": version,
                    # Matches how BSHEEL's existing versions are configured: it goes live on
                    # its own once Apple approves, with nobody needing to press a button.
                    "releaseType": "AFTER_APPROVAL",
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        if not ok:
            die(f"could not create App Store version {version}: {describe(body)}")
        version_id = body["data"]["id"]
        print(f"created App Store version {version}")

    # 2. Attach the build.
    ok, body = patch(f"/v1/appStoreVersions/{version_id}/relationships/build", token,
                     {"data": {"type": "builds", "id": build["id"]}})
    if not ok:
        die(f"could not attach build {build_number} to version {version}: {describe(body)}")
    print(f"attached build {build_number} to version {version}")

    if os.environ.get("APPSTORE_DRY_RUN") == "1":
        print("APPSTORE_DRY_RUN=1 — stopping before submitting to Apple for review")
        return

    # 3. Submit for review. A submission already in flight is not an error to re-running.
    existing = [s for s in paged(f"/v1/apps/{app_id}/reviewSubmissions", token,
                                 {"filter[platform]": PLATFORM,
                                  "fields[reviewSubmissions]": "state"})
                if s["attributes"].get("state") in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW")]
    if existing:
        print(f"a review submission is already in flight ({existing[0]['attributes'].get('state')}) — not creating another")
        return

    ok, body = post("/v1/reviewSubmissions", token, {
        "data": {"type": "reviewSubmissions",
                 "attributes": {"platform": PLATFORM},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}
    })
    if not ok:
        die(f"could not open a review submission: {describe(body)}")
    submission_id = body["data"]["id"]

    ok, body = post("/v1/reviewSubmissionItems", token, {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}
    })
    if not ok:
        die(f"could not add version {version} to the review submission: {describe(body)}")

    ok, body = patch(f"/v1/reviewSubmissions/{submission_id}", token, {
        "data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}
    })
    if not ok:
        die(f"could not submit for review: {describe(body)}")
    print(f"submitted {version} (build {build_number}) to Apple for review")
    print("It goes live automatically once approved. Review usually takes 1-3 days.")


EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "INVALID_BINARY",
}

COMMANDS = {
    "next-build": cmd_next_build,
    "live-version": cmd_live_version,
    "check-version": cmd_check_version,
    "distribute": cmd_distribute,
    "submit": cmd_submit,
}


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in COMMANDS:
        print(f"usage: appstore.py [{' | '.join(COMMANDS)}] <bundle-id> [args...]", file=sys.stderr)
        sys.exit(2)
    COMMANDS[sys.argv[1]](make_token(load_credentials()), sys.argv[2:])


if __name__ == "__main__":
    main()
