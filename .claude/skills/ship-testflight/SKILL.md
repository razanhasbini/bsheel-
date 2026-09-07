---
name: ship-testflight
description: Build BSHEEL and put it on TestFlight. Use when the user says "push to testflight", "ship to testflight", "send a test build", "publish test", or similar. Builds and uploads from this Mac — no GitHub Actions, no CI minutes.
---

# Ship BSHEEL to TestFlight

Builds the iOS app on this machine, uploads it to App Store Connect, and hands it to the
TestFlight groups. Nothing is submitted to Apple for review — that is `ship-appstore`.

Takes about 15 minutes, almost all of it the Flutter build.

## There is also a hook

`git config core.hooksPath scripts/hooks` makes `git push origin main:publish-test` do all of
this on its own. If the user asks to "push to testflight" they may mean either; both end in the
same place. The hook refuses a dirty tree for the reason below.

## Before anything else

Work from the repo root:

```bash
cd /Users/tayseerlaz/Projects/quest-app/4hoursonly
```

Check three things and report them to the user before building:

```bash
git status --short | head            # uncommitted work will NOT be in the build unless it is here
grep -E '^version:' apps/mobile_app/pubspec.yaml
python3 scripts/appstore.py next-build com.questapp.mobileApp
```

The build ships the **working tree**, not a commit. If `git status` is dirty, say so and ask
whether that is intended before spending 15 minutes.

## Check the build will reach someone

Uploading is not distributing. A TestFlight group only offers builds attached to it, so if the
app has no groups the upload succeeds and reaches nobody:

```bash
python3 - <<'PY'
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("asc", "scripts/appstore.py")
asc = importlib.util.module_from_spec(spec); spec.loader.exec_module(asc)
token = asc.make_token(asc.load_credentials())
app = asc.find_app(token, "com.questapp.mobileApp")
groups = asc.paged(f"/v1/apps/{app['id']}/betaGroups", token)
if not groups:
    print("NO TestFlight groups — the build would reach nobody. Create one in App Store Connect first.")
for g in groups:
    a = g["attributes"]
    testers = asc.paged(f"/v1/betaGroups/{g['id']}/betaTesters", token)
    print(f"[{'internal' if a.get('isInternalGroup') else 'EXTERNAL'}] {a.get('name')}: {len(testers)} testers")
PY
```

If there are no groups, stop and tell the user. Do not build.

## Build and upload

```bash
BUILD=$(python3 scripts/appstore.py next-build com.questapp.mobileApp)
VERSION=$(grep -E '^version:' apps/mobile_app/pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*//; s/\+.*//')
scripts/ios_release.sh --version "$VERSION" --build "$BUILD"
```

Run it in the background and poll the log — it is long enough that a foreground call will time
out. The script already refuses to continue if the archive fails, the `.ipa` is missing, or the
built bundle id / version / build number do not match what was asked for.

## Distribute — do not skip this

```bash
python3 scripts/appstore.py distribute com.questapp.mobileApp "$BUILD"
```

This waits for **that specific build number** to finish processing at Apple (usually 5–15
minutes) and makes sure every TestFlight group has it.

It also answers Apple's export-compliance question. A build can be VALID and still sit in
**"Missing Compliance"**, invisible to every tester, until someone opens App Store Connect and
answers "What type of encryption algorithms does your app implement?". That is exactly what
happened to build 74: it processed cleanly, the script said it had shipped, and it reached
nobody. `Info.plist` now declares `ITSAppUsesNonExemptEncryption = false` so Apple stops asking,
and `distribute` answers it over the API for anything uploaded before that.

Two group types behave differently, and both are normal:

- **Internal groups set to "all builds"** receive it automatically the moment processing ends.
  Apple refuses a manual assignment ("Cannot add internal group to a build"), so the script
  reports `(internal, automatic)` and moves on. Nothing is wrong.
- **External groups** cannot see a build until it passes **Beta App Review**, which is a
  separate submission this repo does not automate. The script says so explicitly. If external
  testers need the build, submit it for Beta App Review in App Store Connect.

Never substitute "the newest build" for the build number. Seconds after an upload Apple has not
registered it yet, so operating on the newest build silently acts on the *previous* one and
reports success — a ship that claims to have shipped and did not.

## Build inputs

`scripts/ios_release.sh` compiles in `apps/mobile_app/dart_defines.release.json` and refuses to
run without it. Without those values the app builds, signs and installs perfectly and cannot
reach the API — nothing downstream catches it.

## Report

Tell the user the version, the build number, and which groups now have it. Apple takes a further
few minutes to notify testers.

## When it goes wrong

**"Choose a certificate to revoke"** — the account is at Apple's certificate cap. Check with
`security find-identity -v -p codesigning`. See `docs/PUBLISHING.md`.

**The build uploads but never appears** — Apple emails processing rejections to the team's Apple
ID and they appear in no log. Check that inbox.

**Anything about `Cloud signing permission error`** — the App Store Connect key is not Admin.

Do not retry a failed build through GitHub Actions to "see if it works there". macOS runners on
a private repo bill at 10× and that is how the account's Actions budget was exhausted.
