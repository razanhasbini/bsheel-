---
name: ship-appstore
description: Release BSHEEL to the public App Store. Use when the user says "deploy live", "push to the store", "release to the app store", "publish store", or similar. Builds, uploads and submits to Apple for review — the build goes live to all users once approved.
---

# Release BSHEEL to the App Store

This ships to **every BSHEEL user in the world**. Once Apple approves it, it goes live on its
own — the release type is `AFTER_APPROVAL` and nobody presses a button.

Treat it accordingly. Everything here is reversible only by shipping *another* release through
another 1–3 day review.

## Confirm intent first

Before touching anything, tell the user plainly what is about to happen and get an explicit yes:

- which version is going out, and which version is live now
- that it reaches all users automatically on approval
- that pulling it back means another full review

If the user asked for TestFlight rather than a public release, use `ship-testflight` instead.
"Deploy" is ambiguous; a public release is not the safe default reading. Ask.

## Work from the right repo

**Do not hardcode a path.** This repo is a fork of `quest-app` and ships the
*same* bundle id, `com.questapp.mobileApp`. A stale `cd` into that other tree
builds the wrong code, uploads it successfully, and reports a plausible version
and build number — and for a public release that ships the wrong app to every
user. Locate the root by its own marker and refuse otherwise:

```bash
ROOT=$PWD
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/melos.yaml" ]; do ROOT=$(dirname "$ROOT"); done
cd "$ROOT" || exit 1
# Identify the repo by its architecture, not its name: melos.yaml still says
# "quest_app" in both, and quest-app's own CLAUDE.md mentions Bsheel, so
# neither is a discriminator. Bsheel has a self-hosted backend/ and no
# supabase/ — that is the documented difference between the two.
if [ ! -d backend ] || [ -d supabase ]; then
  echo "REFUSING: $(pwd) is not the Bsheel repo (expected backend/ and no supabase/)."
  exit 1
fi
echo "Releasing from: $(pwd)"
```

If the user invoked this from somewhere else, ask which repo they mean rather
than guessing.

## The version must be new

Apple rejects a version string that is not higher than what is already there. Check **before**
the 15-minute build, not after:

```bash
VERSION=$(grep -E '^version:' apps/mobile_app/pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*//; s/\+.*//')
python3 scripts/appstore.py check-version com.questapp.mobileApp "$VERSION"
```

If it fails, the fix is to bump `version:` in `apps/mobile_app/pubspec.yaml` — for example
`2.0.1` → `2.0.2`. Do that, commit it, and say so. Never work around the check by passing a
different version to the build than the one in pubspec; the two must agree or the repo stops
describing what shipped.

## Check the working tree

The build ships the working tree, not a commit. For a public release this matters more than
anywhere else:

```bash
# Check git's exit code. A failed `git status` prints nothing, which looks
# exactly like a clean tree — that is how a dirty tree ships unnoticed.
git status --short > /tmp/rel-status.txt 2>/tmp/rel-status.err
if [ $? -ne 0 ]; then
  echo "STOP: git status failed, so the tree cannot be verified:"
  cat /tmp/rel-status.err
  echo "Do not proceed with a PUBLIC release on an unverifiable tree."
  exit 1
fi
cat /tmp/rel-status.txt
git log --oneline -3
```

Uncommitted changes will be in the release. Committed changes that are not in the working tree
will not be. If anything is dirty, stop and confirm.

## Build, upload, submit

```bash
BUILD=$(python3 scripts/appstore.py next-build com.questapp.mobileApp)
scripts/ios_release.sh --version "$VERSION" --build "$BUILD"
python3 scripts/appstore.py submit com.questapp.mobileApp "$VERSION" "$BUILD"
```

Run the build in the background and poll — it is far too long for a foreground call.

`submit` waits for that specific build to finish processing, creates the App Store version
(reusing an editable one if it already exists, so a retry is safe), attaches the build, and
submits for review. It will not open a second review submission if one is already in flight.

### Rehearsing

To do everything except the irreversible step:

```bash
APPSTORE_DRY_RUN=1 python3 scripts/appstore.py submit com.questapp.mobileApp "$VERSION" "$BUILD"
```

That creates the version and attaches the build but stops before submitting. Worth doing the
first time, so the first real submission is not also the first test.

## Report

Tell the user the version and build submitted, and that Apple usually takes 1–3 days and emails
the team's Apple ID either way — approvals and rejections both arrive only by email and appear
in no log or dashboard this repo can read.

## When it goes wrong

**"There is already a version with this version string"** — an editable version exists in App
Store Connect. The script reuses it when the version matches and stops with a readable message
when it does not. Resolve it in App Store Connect rather than forcing a different number.

**"A review submission is already in flight"** — cancel the existing one in App Store Connect
first. Do not open a second.

**Apple rejects the build during processing** — the build silently never appears. Check the
email on the team's Apple ID.

## Build inputs that are easy to lose

`scripts/ios_release.sh` compiles in `apps/mobile_app/dart_defines.release.json` and refuses to
run without it. Those values (backend URL, anon key, Google client ids) are compiled into the
binary — a build made without them signs, uploads and installs perfectly, and is dead on launch.
Never bypass that check.

`--obfuscate` is applied for every release, per the M17 audit. The symbol map lands in
`build/symbols/` and is the only way to read a crash report from a shipped build. Keep it; never
ship it.

## What this skill must never do

- Submit without the user explicitly confirming a public release
- Change the version to get past `check-version`
- Enable a public TestFlight link or an external group as a shortcut
- Retry through GitHub Actions; macOS runners bill at 10× on a private repo
