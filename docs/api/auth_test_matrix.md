# Auth Test Matrix — every sign-in / sign-up scenario

Audited 2026-07-14 against the self-hosted backend (api.bsheel.app).
Legend: ✅ automated (unit/widget test) · 🔬 verified in code review · 📱 needs one manual device pass · 🖥️ server-config dependent.

## 1. Email sign-up

| # | Scenario | Expected behavior | Status |
|---|----------|-------------------|--------|
| 1.1 | Happy path (valid username/email/password, 13+ checked) | Account created; `handle_new_user` trigger creates profile with chosen username; confirmations ON → "check your email" + routed to login; OFF → session starts, router sends to walkthrough | 🔬 + 📱 |
| 1.2 | Email already registered (confirmed account) | Supabase anti-enumeration returns fake user with EMPTY `identities` — app detects this and shows "already registered — log in or use FORGOT PASSWORD" instead of a phantom "check your email" | 🔬 (fixed 2026-07-14) |
| 1.3 | Email already registered (unconfirmed) | Supabase re-sends the confirmation email, `identities` non-empty → normal "check your email" message. Correct behavior | 🔬 |
| 1.4 | Username already taken | DB unique violation → mapped to "already taken", routed to the username field | ✅ mapper + 🔬 field routing |
| 1.5 | Username invalid (< 3 chars, symbols) | Client-side validator blocks pre-submit | 🔬 |
| 1.6 | Weak password (< 10, missing case/digit, contains username/email/banned words) | `validatePassword` blocks pre-submit with specific hints | ✅ password_policy_test (8 cases) |
| 1.7 | Mixed-case email `Foo@Bar.com` | Lower-cased before signUp — one canonical account | 🔬 |
| 1.8 | Under-13 (checkbox unchecked) | Blocked pre-submit with age error; `age_verified` lands on profile via trigger metadata when checked | 🔬 |
| 1.9 | Network drop mid-signup | Error mapped to "No internet connection" | ✅ mapper |
| 1.10 | Rate limited | "Too many attempts" | ✅ mapper |

## 2. Email sign-in

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 2.1 | Happy path | Session starts; FCM token saved on `signedIn` event; analytics identify; router → home (or walkthrough if onboarding incomplete) | 🔬 + 📱 |
| 2.2 | Wrong password / unknown email | One generic "Incorrect email or password." (no account enumeration) | ✅ mapper |
| 2.3 | Mixed-case email | Normalized (trim + lowercase) to match signup — same account | ✅ login_credentials_test (fixed 2026-07-14) |
| 2.4 | Unconfirmed email | "Please confirm your email" + one-tap **RESEND CONFIRMATION EMAIL** link (enumeration-safe copy) | ✅ mapper + 🔬 (resend added 2026-07-14) |
| 2.5 | Suspended/banned account logs in | Login succeeds (read-only access by design); every write action blocked client-side by `guardAccountAction` AND server-side by migration `0123_banned_user_write_guard` | 🔬 |
| 2.6 | Session expires while app open | `AuthNotifier` catches refresh errors, nulls the session, router bounces to login; module caches wiped on sign-out event so user A's data can't leak to user B | 🔬 |
| 2.7 | Empty fields | Client-side field errors | 🔬 |

## 3. Google sign-in (native id-token flow)

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 3.1 | First-time Google user | New auth user; trigger creates profile with generated `user_XXXXXXXX` username; age modal confirmed pre-flow; `age_verified` persisted post-auth | 🔬 + 📱 |
| 3.2 | Returning Google user | Same account; no duplicate profile (`ON CONFLICT (id) DO NOTHING`) | 🔬 |
| 3.3 | **Google email == existing email/password account** | GoTrue links the Google identity to the SAME user (automatic linking, verified emails) → same profile/XP. No duplicate | 🖥️ + 📱 one-time verify on self-host |
| 3.4 | User cancels the Google sheet | Silent return (no error toast) — cancellation filtered | 🔬 |
| 3.5 | Declines age modal | Flow aborts BEFORE any account is created | 🔬 |
| 3.6 | Missing GOTRUE_EXTERNAL_GOOGLE_* config on self-host | Sign-in fails with an error (fails safe — no mis-linking) | 🖥️ verify env on Contabo |
| 3.7 | Social login remotely disabled (`socialLoginEnabledProvider`) | Buttons hidden entirely | 🔬 |

## 4. Apple sign-in (native, nonce-protected)

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 4.1 | First-time / returning | Same as 3.1/3.2; replay attacks blocked by hashed nonce | 🔬 + 📱 |
| 4.2 | Apple email == existing account email | Linked to same user (as 3.3) | 🖥️ + 📱 |
| 4.3 | **"Hide My Email" relay address** | Different email → legitimately a SECOND account. Platform behavior, cannot be prevented — document in support copy | 🔬 (accepted) |
| 4.4 | User cancels Apple sheet | Silent return | 🔬 |
| 4.5 | Apple returns no identity token | Explicit AuthException surfaced via mapper | 🔬 |

## 5. Cross-provider duplicate matrix (same person, same email)

| First → then | Result |
|---|---|
| Email/password (confirmed) → Google | One account (identity linked) 🖥️ |
| Email/password (confirmed) → Apple (real email) | One account 🖥️ |
| Google → email signup, same address | Anti-enumeration fake user; app now detects empty `identities` and says "already registered" (fix 1.2). To add a password: FORGOT PASSWORD flow works — recovery email sets a password on the same account | 🔬 |
| Google → Apple (same Gmail) | One account 🖥️ |
| Apple (Hide-My-Email) → anything | Separate account (relay email ≠ real email) — expected | 🔬 |
| Email/password (UNconfirmed) → Google same address | GoTrue version-dependent: may create a second user. **One-time manual test required on api.bsheel.app**; mitigation if needed: enable `GOTRUE_MAILER_AUTOCONFIRM` or clean unconfirmed rows | 📱🖥️ |

## 6. Forgot / reset password

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 6.1 | Known email | Recovery email; deep link `https://admin.bsheel.app/reset-password` → app link opens reset page (requires admin.bsheel.app AASA/assetlinks live) | 📱 after web deploy |
| 6.2 | Unknown email | Identical success UI (enumeration-safe — even network errors show success) | 🔬 |
| 6.3 | Expired/used reset link | `updatePassword` fails → "Your reset link has expired or was already used" | ✅ mapper (fixed 2026-07-14) |
| 6.4 | New password fails policy (incl. contains email local-part) | Blocked client-side; recovery session's email fed to the validator | 🔬 |
| 6.5 | Transient failure during update | Recovery flag intentionally NOT cleared → user can retry without a new email | 🔬 |
| 6.6 | Reset while already signed in | `/reset-password` exempt from the logged-in redirect | ✅ route_guards_test |

## 7. Routing / session guards (fully automated)

`route_guards_test.dart` covers: signed-out → login bounce for every protected route; auth routes reachable signed-out; splash exemption; signed-in bounce off auth pages; reset-password exemption (signed-in AND mid-onboarding); onboarding gate + no-loop; null-onboarding no-bounce.

## 8. Sign-out / account deletion

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 8.1 | Sign out | FCM token deleted BEFORE session ends (RPC needs auth.uid); all module caches reset; router → login | 🔬 |
| 8.2 | Delete account | Confirmation dialog with typed confirmation; queued via `account_deletion_queue` (0122); drained by cron → `admin_manage_user` edge fn | 🔬 |
| 8.3 | Silent token expiry (not user-initiated) | `AuthNotifier` also resets caches on `signedOut` event — no data bleed between accounts | 🔬 |

## Fixes shipped with this audit (2026-07-14)

1. Login email now normalized (trim + lowercase) to match signup — prevents case-variant "wrong password" confusion.
2. Signup detects Supabase's anti-enumeration response (`identities == []`) — no more phantom "check your email" for already-registered addresses.
3. "RESEND CONFIRMATION EMAIL" one-tap action on login when the account is unconfirmed (enumeration-safe messaging), incl. new `AuthRepository.resendSignupConfirmation`.
4. Expired-reset-link errors now map to an actionable message instead of raw "Auth session missing!".
5. `authRedirect` refactored to take a plain location string → the full redirect matrix is now unit-tested.

## Outstanding one-time manual checks (need device + live server)

- [ ] 3.3 / 4.2: same-email cross-provider linking on api.bsheel.app (one row in `auth.users`?)
- [ ] 5-last: unconfirmed-email + OAuth same-address behavior on the deployed GoTrue version
- [ ] 3.6: `GOTRUE_EXTERNAL_APPLE_*` / `GOOGLE_*` envs present on the Contabo box
- [ ] 6.1: reset-email deep link end-to-end once admin.bsheel.app serves `/reset-password` + `.well-known` files
