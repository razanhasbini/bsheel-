# Auth test matrix

Every sign-up, sign-in, recovery and session scenario, with the error code the
API returns. Clients branch on `error.code`, never on the message.

Legend: **A** automated in `backend/test/` · **C** verified by code review ·
**D** needs a device pass · **P** needs a live provider (Google, Apple, email)

> Rewritten 2026-09-08. The previous version described Supabase GoTrue
> behaviour — anti-enumeration responses with empty `identities`, automatic
> cross-provider identity linking, `GOTRUE_*` environment variables. None of
> that applies any more: the API owns auth, and its semantics are different in
> ways that matter (noted per row).

## 1. Registration — `POST /auth/register`

| # | Scenario | Expected | Status |
|---|---|---|---|
| 1.1 | Valid email, username, password, `ageVerified: true` | Account created. With `AUTH_EMAIL_CONFIRMATION_REQUIRED=true` returns `{confirmationRequired: true}` and no session; otherwise returns a token pair | A |
| 1.2 | Email already registered | `409 EMAIL_TAKEN` | A |
| 1.3 | Username already taken | `409 USERNAME_TAKEN` | A |
| 1.4 | Both collide | Whichever constraint fires first; both codes are field-attributable | A |
| 1.5 | `ageVerified: false` or absent | `403 AGE_VERIFICATION_REQUIRED`, before any row is written | A |
| 1.6 | Password fails policy | `400`, rejected before hashing | A |
| 1.7 | Username fails the format rule | `400` from DTO validation | A |
| 1.8 | Mixed-case email `Foo@Bar.com` | Lower-cased before insert, so one canonical account | C |
| 1.9 | Unknown field in the body | `400` — `forbidNonWhitelisted` rejects rather than ignores | A |

**Deliberate difference from the legacy system.** Registration now tells the
caller *which* value collided. Supabase deliberately returned a fake success to
avoid account enumeration, and the app had to detect an empty `identities`
array to show a useful message. That trade is now explicit: signup reveals that
an email is registered, because a signup form that cannot say so is a worse
product for a consumer app. Recovery (§4) remains enumeration-safe, which is
where it actually matters.

## 2. Sign-in — `POST /auth/login`

| # | Scenario | Expected | Status |
|---|---|---|---|
| 2.1 | Correct credentials | Token pair; `last_login` touched | A |
| 2.2 | Wrong password | `401 INVALID_CREDENTIALS` | A |
| 2.3 | Unknown email | `401 INVALID_CREDENTIALS` — identical to 2.2, no enumeration | A |
| 2.4 | Unconfirmed email | `403 EMAIL_NOT_CONFIRMED`; client offers "resend confirmation" | A |
| 2.5 | Suspended or banned | `403 ACCOUNT_RESTRICTED` with the status in the message | A |
| 2.6 | Mixed-case email | Normalised, matches the account created in 1.8 | A |
| 2.7 | Empty fields | `400` from DTO validation | A |
| 2.8 | Malformed email | `400`, before any database read | A |

Note 2.5 differs from legacy, which let a banned user sign in read-only and
blocked writes at the row level. The API refuses the session outright.

## 3. OAuth — `POST /auth/oauth`

| # | Scenario | Expected | Status |
|---|---|---|---|
| 3.1 | First-time Google user | Identity verified server-side against Google's keys; account and profile created with a generated username | P |
| 3.2 | Returning Google user | Same account, no duplicate identity row | P |
| 3.3 | First-time Apple user, nonce-protected | As 3.1; a replayed nonce is rejected | P |
| 3.4 | Apple "Hide My Email" relay address | Legitimately a separate account — the relay address is a different identity. Platform behaviour; document it in support copy | C |
| 3.5 | Invalid or expired ID token | `401`, no account created | C |
| 3.6 | `OAUTH_GOOGLE_CLIENT_IDS` / `OAUTH_APPLE_CLIENT_IDS` unset | Verification fails closed — no session | C |
| 3.7 | Social login disabled via `app_config` | Buttons hidden. **The flag now fails closed**: an absent row means off | A |
| 3.8 | Restricted account signs in with OAuth | `403 ACCOUNT_RESTRICTED` | C |

**Deliberate difference.** Supabase auto-linked a Google identity to an
existing password account with the same verified email. The API does not link
implicitly — an identity is matched on `(provider, provider_subject)`. Silent
linking on a matching email address is a documented account-takeover vector if
the provider's email verification is ever weaker than assumed. If product wants
linking, it should be an explicit, authenticated "connect account" action.
**This changes observable behaviour for a user who signed up with a password
and then taps "Continue with Google" using the same address**, so it needs a
product decision and support copy.

## 4. Password recovery

| # | Scenario | Expected | Status |
|---|---|---|---|
| 4.1 | `POST /auth/password-recovery`, known email | `204`. A one-time token is generated, SHA-256 indexed, AES-256-GCM encrypted at rest, valid 1 hour, and delivered **only by the worker** | A |
| 4.2 | Same, unknown email | **Identical `204`.** No enumeration. The API never returns the raw token | A |
| 4.3 | `POST /auth/password-recovery/complete` with a valid token | Password set; token consumed | A |
| 4.4 | Reusing a consumed token | Rejected — single use | A |
| 4.5 | Expired token | Rejected | A |
| 4.6 | Malformed token | Rejected with the same error as 4.4/4.5, so probing learns nothing | A |
| 4.7 | New password fails policy | `400`; the token is **not** consumed, so the user can retry | A |
| 4.8 | Deep link `/reset-password?token=…` | Opens the reset page and consumes the token. Requires AASA/assetlinks live on the origin | D |

## 5. Email confirmation

| # | Scenario | Expected | Status |
|---|---|---|---|
| 5.1 | `POST /auth/email-confirmation/complete` with a valid token | Email marked verified; login now succeeds | A |
| 5.2 | Reused or expired token | Rejected; the admin-web page shows "invalid or has expired" | A |
| 5.3 | `POST /auth/email-confirmation/resend` for an unconfirmed account | `204`, new token queued | A |
| 5.4 | Resend for an unknown or already-confirmed email | Identical `204` — enumeration-safe | A |

## 6. Sessions, refresh and logout

| # | Scenario | Expected | Status |
|---|---|---|---|
| 6.1 | `POST /auth/refresh` with a valid token | New pair; the old session is marked rotated | A |
| 6.2 | **Replaying an already-rotated refresh token** | `401 REFRESH_TOKEN_REUSED` **and the whole token family is revoked** — this is the theft-detection path | A |
| 6.3 | Refresh token whose hash does not verify | `401 INVALID_REFRESH_TOKEN`, family revoked | A |
| 6.4 | Refresh after a server-side revocation (`tokenVersion` bumped) | `401 SESSION_REVOKED`, family revoked | A |
| 6.5 | Refresh on a revoked or expired session | `401 INVALID_REFRESH_SESSION` | A |
| 6.6 | Concurrent refreshes from one client | The client serialises refresh in `ApiClient`, so only one request spends the token. Without that, 6.2 would fire on a legitimate client | A (Dart) |
| 6.7 | `POST /auth/logout` | Session revoked; a missing token is a no-op, not an error | A |
| 6.8 | Access token expires mid-session | Client refreshes transparently on the first 401 and retries once | A (Dart) |
| 6.9 | Refresh fails unrecoverably | Client emits `signedOut`, clears the token store, wipes module caches so one user's data cannot leak to the next, and the router bounces to login | C |
| 6.10 | Authenticated route with no token | `401` | A |
| 6.11 | Authenticated route with a malformed token | `401` | A |
| 6.12 | Admin route with a valid non-admin token | `403` — authentication and authorisation are separate layers | A |

## 7. Routing and guards (client)

`route_guards_test.dart` covers: signed-out bounce for every protected route,
auth routes reachable while signed out, splash exemption, signed-in bounce off
auth pages, `/reset-password` exempt from the signed-in redirect and from the
onboarding gate, and the onboarding gate with no redirect loop.

## 8. Account deletion

| # | Scenario | Expected | Status |
|---|---|---|---|
| 8.1 | `POST /account/deletion` | Queued in `account_delete_requests`; drained by the worker | A |
| 8.2 | Device token cleanup on sign-out | Token deregistered before the session ends, while the call is still authorised | C |
| 8.3 | Username after deletion | Retained as a tombstone so it cannot be immediately re-registered | A |

## Outstanding — needs a live provider or a device

- 3.1–3.3, 3.6: Google and Apple sign-in against real provider keys.
- 4.1, 5.3: real email delivery through `EMAIL_DELIVERY_WEBHOOK_URL`.
- 4.8: reset deep link end to end, once `.well-known` files are served.
- A product decision on §3's implicit-linking change, plus the support copy.
