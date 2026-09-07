# Deep-link verification (C4, 2026-05-17 audit)

Both Android App Links and iOS Universal Links need a cryptographic
proof, served from the same web origin the link points at, that
the app is the legitimate handler. Without these files Android falls
back to a chooser sheet ("Open with") and iOS falls back to opening
the link in Safari — and in both cases a malicious app on the device
can register the same scheme and intercept links (including the
password-reset deep link).

This folder holds the two template files. Replace the placeholders
with real credentials and deploy them at the indicated URLs.

## 1. Android — `assetlinks.json`

Deploy at: `https://admin.bsheel.app/.well-known/assetlinks.json`

Steps:
1. Get the SHA256 fingerprint of the **production** signing certificate:
   ```
   keytool -list -v -keystore <prod-keystore.jks> -alias <key-alias>
   ```
   Copy the `SHA256` line value (colon-separated hex).
2. Edit `assetlinks.json.template`, paste the fingerprint into
   `sha256_cert_fingerprints`, and rename to `assetlinks.json`.
3. Place the file at `apps/admin_web/web/.well-known/assetlinks.json` —
   the Flutter web build copies `web/` into `build/web`, so the Contabo
   server serving `admin.bsheel.app` picks it up on the next deploy.
4. Verify: `curl https://admin.bsheel.app/.well-known/assetlinks.json`
5. Test: `adb shell pm verify-app-links --re-verify com.questapp.mobileApp`

## 2. iOS — `apple-app-site-association`

Deploy at: `https://admin.bsheel.app/.well-known/apple-app-site-association`

Steps:
1. Find the Apple Team ID in
   [https://developer.apple.com/account](https://developer.apple.com/account)
   under "Membership details".
2. Edit `apple-app-site-association.template`, replace
   `REPLACE_WITH_TEAM_ID` with the 10-character Team ID, drop the
   `.template` suffix.
3. Serve at the exact path (no extension) with `Content-Type: application/json`.
   Place it at `apps/admin_web/web/.well-known/apple-app-site-association`
   (no extension) and make sure the web server on `admin.bsheel.app`
   serves it with the JSON content type.
4. Verify: `curl -I https://admin.bsheel.app/.well-known/apple-app-site-association`
   (should return 200, `Content-Type: application/json`)

## Once deployed

The AndroidManifest already has `android:autoVerify="true"`, and the
iOS entitlements already include the Associated Domains entry. As
soon as the two files above are reachable on the production domain,
both platforms will start trusting the app as the only legitimate
handler for `https://admin.bsheel.app/{post,user,join}/*`.
