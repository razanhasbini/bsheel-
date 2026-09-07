# Publishing BSHEEL

Two branches, two destinations. Nothing ships from `main`.

| Push to | What happens | Who sees it |
|---|---|---|
| `main` / `dev` | analyse + test only (existing `CI` workflow) | nobody |
| `publish-test` | build → upload → distribute to TestFlight | your testers |
| `publish-store` | build → upload → **submit to Apple for review** | everyone, once approved |

```bash
git push origin main:publish-test     # ship a TestFlight build
git push origin main:publish-store    # release to the App Store
```

Both branches build with the identical script (`scripts/ios_release.sh`), so a TestFlight build
and a store build are the same process — only what happens afterwards differs.

---

## ⚠️ Do this first: revoke the leaked API key

`apps/mobile_app/ios/AuthKey_V5L2554CT7.p8` was committed in `2a9c42b` (2026-03-28) and deleted
in `53632d0` the same day. **Deleting a file does not remove it from git history.** The key is
still recoverable by anyone who can read this repository:

```bash
git show 2a9c42b:apps/mobile_app/ios/AuthKey_V5L2554CT7.p8   # prints a live private key
```

That key can upload builds to the App Store as this team. Treat it as compromised.

1. Revoke key `V5L2554CT7` at <https://appstoreconnect.apple.com/access/integrations/api>
2. Create a replacement with the **Admin** role (see below) and store it as repository secrets
3. Optionally rewrite history to purge the blob — but revoking is the fix that actually matters,
   because every existing clone already has it

`.gitignore` now covers `AuthKey_*.p8`, so this cannot recur.

---

## One-time setup

### Repository secrets

Three, set once by a repo admin:

```bash
gh secret set ASC_KEY_P8    --repo laythayache/4hoursonly < ~/Downloads/AuthKey_XXXXXXXXXX.p8
gh secret set ASC_KEY_ID    --repo laythayache/4hoursonly
gh secret set ASC_ISSUER_ID --repo laythayache/4hoursonly
```

> The key's role must be **Admin**, not App Manager. App Manager can create provisioning
> profiles but not the *distribution certificate* that cloud signing needs, and the only symptom
> is `Cloud signing permission error` / `No profiles were found` forty minutes into a run. A
> key's role cannot be edited after creation — revoke it and make a new one.

A fourth secret carries a required build input that is deliberately gitignored:

```bash
base64 -i apps/mobile_app/ios/Runner/GoogleService-Info.plist \
  | gh secret set GOOGLE_SERVICE_INFO_PLIST --repo laythayache/4hoursonly
```

Without it the Xcode build fails four minutes in with `Build input file cannot be found`. The
workflow writes the file before building and deletes it afterwards, so the repo's decision to
keep it out of git is preserved. Re-run that command if the Firebase config ever changes.

### The signing certificate — why it is a secret and not created on demand

Two more secrets carry one iOS signing identity:

| Secret | What it is |
|---|---|
| `IOS_SIGNING_P12` | base64 of a `.p12` holding the certificate **and its private key** |
| `IOS_SIGNING_P12_PASSWORD` | the password that `.p12` was exported with |

This is the difference between a pipeline that works twice and one that works forever.

A signing certificate is two halves: a record Apple keeps, and a **private key that only exists
on the machine that made it**. A GitHub runner is a fresh, empty Mac, so
`-allowProvisioningUpdates` had nothing to reuse and created a *new* certificate on every run —
then the runner was destroyed, taking the private key with it. Twelve runs filled Apple's
per-team cap and every build afterwards failed with:

> Choose a certificate to revoke. Your account has reached the maximum number of certificates.

Importing one certificate we own means Xcode finds an identity it can already use and creates
nothing. The runner builds a temporary keychain, imports it, and the keychain dies with the job.

To rotate it (it expires 2027-08-30):

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout ci.key -out ci.csr \
  -subj "/CN=BSHEEL CI Signing/O=I EVENTS/C=LB"
# create the certificate from ci.csr at
# https://developer.apple.com/account/resources/certificates  (type: Apple Development)
# then, with the downloaded .cer:
openssl x509 -inform DER -in ci.cer -out ci.pem
# The legacy algorithms are REQUIRED. OpenSSL 3 defaults to encryption macOS's Security
# framework cannot read, and `security import` fails with the actively misleading
# "MAC verification failed during PKCS12 import (wrong password?)" — the password is fine.
openssl pkcs12 -export -inkey ci.key -in ci.pem -out ci.p12 \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout pass:SOMETHING
base64 -i ci.p12 | gh secret set IOS_SIGNING_P12 --repo laythayache/4hoursonly
printf '%s' SOMETHING | gh secret set IOS_SIGNING_P12_PASSWORD --repo laythayache/4hoursonly
```

Never commit `ci.key`, `ci.p12` or the password. They are the one thing here that can sign as
your team.

The Team ID (`JMDKX9TYX6`) and bundle id (`com.questapp.mobileApp`) are not secrets and live in
`scripts/ios_release.sh`.

### Restricting who can release

`publish-store` releases to the public, so only one person should be able to trigger it.

**Already enforced, no setup needed:** the `guard` job in `publish-store.yml` fails the run
unless `github.actor` is `TayseerLaz`. Anyone else's push to that branch stops before a single
byte is built, and nothing reaches Apple.

**Additional hardening (needs a repo admin):** GitHub cannot restrict *pushes* to a named person
on a **user-owned** repository — the "restrict who can push" list is an organisation feature. To
get the branch itself locked down:

1. Move `4hoursonly` into a GitHub organisation, then
2. **Settings → Rules → New ruleset**
   - Target: `publish-store`
   - Enable **Restrict updates**, **Restrict deletions**, **Block force pushes**
   - Bypass list: `TayseerLaz` only

Until that happens the actor check is the real protection, and it is enough to stop an accidental
release — it just cannot stop someone from writing to the branch.

---

## Versions

`apps/mobile_app/pubspec.yaml` owns the marketing version:

```yaml
version: 2.0.2+75    # ← 2.0.2 is what users see; the +75 is ignored
```

- **The build number is taken from Apple**, not from pubspec, so builds shipped from CI and from
  a Mac share one increasing sequence and can never collide.
- **`publish-store` refuses to run if the version is not higher than what is already on the App
  Store**, and it checks this *before* the forty-minute build rather than after. A forgotten bump
  costs thirty seconds.
- `publish-test` has no such rule: TestFlight is happy to take many builds of one version.

At the time of writing the App Store has **2.0.1**, and `pubspec.yaml` says **1.1.8** — so a push
to `publish-store` today would correctly stop and tell you to bump it.

---

## Shipping by pushing, without GitHub Actions

GitHub bills macOS runners at 10x on a private repo and this account's Actions budget is gone,
so `publish-test` and `publish-store` never get a machine. A pre-push hook does the same job on
your own Mac for nothing:

```bash
git config core.hooksPath scripts/hooks    # once per clone
git push origin main:publish-test          # builds, uploads, distributes, THEN pushes
```

The hook runs **before** the push and aborts it if the build fails, so a publish branch on the
remote always means "this shipped" rather than "someone pushed at it".

It refuses a dirty working tree. The build ships the tree while the push ships commits, and a
branch that does not match what shipped is worse than no branch — that is the whole point of
having the branch.

`publish-store` additionally re-checks the version against the live App Store and makes you type
`RELEASE`, because the difference between the two branches is nine testers and every user in the
world.

- Skip it for one push: `git push --no-verify`
- Turn it off entirely: `git config --unset core.hooksPath`

It only fires from the machine where it is configured — Layth pushing from his own Mac gets
nothing. It is a stand-in for the CI workflows, not a replacement. Delete the setting once
Actions billing works and the branches will do it properly for everyone.

## Releasing from a Mac

Same script CI uses, when you would rather not wait:

```bash
scripts/ios_release.sh --version 2.0.2 --build "$(python3 scripts/appstore.py next-build com.questapp.mobileApp)"
python3 scripts/appstore.py submit com.questapp.mobileApp 2.0.2 <build>
```

`--no-upload` signs for real and stops before uploading, which is the honest way to check a
release builds without spending a build number.

---

## Rehearsing a store release

`Actions → Publish to the App Store → Run workflow → dry run: true` does everything — builds,
uploads, creates the App Store version, attaches the build — and stops before submitting to
Apple. Use it the first time, so the first real submission is not also the first test.

---

## What the store job actually does

1. Refuses the run unless you are the release owner
2. Refuses a version that is not higher than what is live
3. Analyses and tests
4. Asks Apple for the next build number
5. Builds, signs, exports and verifies the `.ipa` (bundle id, version, build number, icon) before
   spending an upload
6. Uploads, then **waits for that specific build to finish processing** — by number, not "the
   newest build", because seconds after an upload Apple has not registered it yet and operating
   on the previous build looks like success
7. Creates the App Store version (reusing an editable one if it exists, so a retry is safe)
8. Attaches the build and submits for review

Release type is `AFTER_APPROVAL`, matching how BSHEEL's existing versions are configured: it goes
live on its own once Apple approves. Change `releaseType` in `scripts/appstore.py` if you would
rather press the button yourself.

---

## Known traps

**The build is VALID but no tester can see it** — it is probably stuck on "Missing
Compliance". `Info.plist` declares `ITSAppUsesNonExemptEncryption = false` so Apple should not
ask, and `appstore.py` answers it over the API as a fallback. That answer means "only standard
exempt encryption" (HTTPS to Supabase and Firebase). **If BSHEEL ever ships its own
cryptography, that declaration stops being true and must change** — it is a legal statement,
not a checkbox.

**"Cloud signing permission error"** — the API key is not Admin. See above.

**The build uploads but never appears** — Apple emails processing rejections to the team's Apple
ID and they appear in no log. Check that inbox.

**"There is already a version with this version string"** — an editable version for that number
already exists in App Store Connect. The script reuses it if the version matches, and stops with
a readable message if it does not.

**A review submission is already in flight** — the script will not open a second one. Cancel the
existing submission in App Store Connect first.
