# Testing the CAMARA verification pipeline

Everything here was measured against Nokia's simulator, not taken from the
docs — where the two disagree, the docs are noted as wrong.

## The trap: the simulator's identities are inverted

Nokia answers **per phone number**, not per position or per request. A
device at its own retrieved coordinates with a 10 km radius still gets
`FALSE` if its number says `FALSE`.

| identity | Number Verification | Location Verification |
|---|---|---|
| `+99999991000` | **TRUE** — can sign in | **FALSE** — never at the place |
| `+99999991001` | FALSE — cannot sign in | **TRUE** — always at the place |
| `+99999991003` | — | PARTIAL, with **no** `matchRate` |
| `+99999991002` | — | UNKNOWN |
| `+99999990503` | — | provider error (returns 500, not 503) |

Nokia's published table has **1002 and 1003 the other way round**. The live
API is the authority; the code follows the API.

**The consequence that matters:** the only number that can sign in is the
one that always fails location. So a normally-created account can never
produce a `SUPPORTED` location outcome, and "good proof + location true"
is unreachable through the UI alone.

### Working around it

Location evidence reads `users.phone_number`. Sign in normally with
`+99999991000`, then repoint that column:

```sql
UPDATE users SET phone_number = '+99999991001' WHERE id = '<user-id>';
```

Verified: the account then returns `SUPPORTED` → `APPROVED`. The change
survives re-sign-in, because the account is matched on its `auth_identities`
row rather than this column. Set it back to `+99999991000` when you want the
contradiction case again.

This is a local-testing device only. It is not a backdoor in production:
the column is only ever written by a completed Number Verification.

## Outcome mapping

| CAMARA result | Evidence outcome | Effect on a submission |
|---|---|---|
| `TRUE` | SUPPORTED | counts toward approval |
| `FALSE` | CONTRADICTED | grounds for rejection |
| `PARTIAL` + `matchRate >= 80` | SUPPORTED | counts toward approval |
| `PARTIAL` + `matchRate < 80` | CONTRADICTED | grounds for rejection |
| `PARTIAL`, **no** `matchRate` | UNAVAILABLE | HUMAN_REVIEW |
| `UNKNOWN` | UNAVAILABLE | HUMAN_REVIEW |
| provider error / timeout | UNAVAILABLE | HUMAN_REVIEW |

A rejection must rest on a positive statement from the network. Absent or
unquantified data goes to a human — never to an automatic rejection. Pinned
by `backend/test/location-verification-mapping.spec.ts`.

## Seeing it work

Run the app in debug and tap the floating **CAMARA** badge (any screen).
Sign in first — the demo asks about *your* verified device. It makes the
calls live and prints the endpoint, the question, the answer and the
round-trip time, then the four-outcome matrix.

## What still gates the full matrix

- **Geofencing events** — Nokia POSTs entry/exit to a public webhook, so
  they cannot arrive at a laptop. Needs the deployed backend and
  `CAMARA_GEOFENCING_SINK_BASE_URL` pointing at it. Subscription creation
  and deletion work locally — but only for a device the network knows; see
  the section below, which is the thing that actually stopped this working.
- **`map_location_evidence`** — still has readers and no writer (#53). The
  hidden-quest geofence unlock stays blocked on it.

CV is no longer on this list. `CV_PROVIDER=local` (the default) binds the
#47 vision cascade as the agent's CV provider, so media analysis arrives
with a relevance score and a typed observation list and content-based
decisions no longer fall to HUMAN_REVIEW for want of eyes. It needs
`AI_VERIFICATION_ENABLED=true` (now the default) and an `OPENAI_API_KEY`
(never a default — supply it); without a key it degrades to exactly what
`CV_PROVIDER=none` returned, which is the honest answer rather than a
guess.

The same is true one level up: `CAMARA_ENABLED` and `OPENAI_AGENT_ENABLED`
default to true as of the defaults change, so a laptop with no keys runs
the whole pipeline and sends everything to the human queue. If the agent
looks broken, check the keys before the code — and remember a deployed
environment (`NODE_ENV=production|staging`) refuses to boot without them
rather than degrading.

So you can test good-proof and bad-proof against every location outcome
**except** the ones that need a real geofence entry event, which need the
live server regardless of CV.

## Geofencing needs a device the network knows

This cost a day, so it is written down in full.

Every geofence in the local deployment was failing, and the recorded reason
was `Provider returned HTTP 404`. A 404 from this gateway has a well-known
meaning in this repo — `camara-client.factory.ts` documents that the wrong
`x-rapidapi-host` produces `404 "API doesn't exists"` — so the obvious
reading was that geofencing was mis-routed or not entitled.

It was neither. Measured against the live gateway on 2026-09-13, on the same
API key and the same SDK client that Location Verification succeeds on:

| Request | Answer |
|---|---|
| `POST geofencing-subscriptions/v0.3/subscriptions`, device `+99999991001` | **201 Created** |
| the same request, device `+96170123456` | **404** `{"detail": "Target not found"}` |
| `POST geofencing-subscriptions/v0/…`, `…/v0.4/…`, `…/v1/…` | 404 `Endpoint … does not exist` |

Two different 404s, and the body is the only thing that tells them apart —
which is why `describeCamaraError` now keeps the problem-details `detail`
and `describeSubscriptionFailure` maps 404 / 403 / 401 to three different
sentences. "HTTP 404" sent the investigation to the wrong place.

**The product is entitled and the routing is correct. Nokia simply will not
watch a device it does not know**, and the simulator knows only its own
MSISDNs. Every seeded account here has a `+961` number, so on a
simulator-backed deployment *every* geofence failed, on every quest.

So a deployment with `CAMARA_DEMO_PERSONAS_ENABLED=true` opens the watch
against `GEOFENCE_SIMULATOR_DEVICE` (`+99999991001` — the identity whose
Location Verification agrees with the Budapest coordinate Location Retrieval
reports, so the three capabilities tell one story) and records the
subscription with `origin = 'NOKIA_SIMULATOR'`. That flag is refused on
production by the environment schema, so a live deployment cannot take this
branch: it keeps asking about the player's own device and now fails with a
sentence that says what to do about it.

**What the stand-in may and may not be used for.** The subscription is real
— Nokia holds it, `GET …/subscriptions/{id}` returns it, cancelling it is a
real call — but its subject is not the player. So
`CamaraEvidenceAdapter.geofencing` will not turn silence on it into
`CONTRADICTED`; only `origin = 'NOKIA'` earns that. An entry event on it is
usable and labelled `NOKIA_CALLBACK_SIMULATOR_DEVICE`, because the network
really did speak — just not about this player. `camara-evidence.adapter.spec.ts`
pins both halves, and migration `0051` carries the reasoning.

To verify it end to end, assign a destination quest and look:

```sql
SELECT status, origin, array_length(provider_subscription_ids, 1), failure_reason
FROM geofencing_subscriptions ORDER BY created_at DESC LIMIT 1;
--  active | NOKIA_SIMULATOR | 2 |
```

Two provider subscriptions, because Nokia enforces one event type each
(`area-entered`, `area-left`).

## Local stack

```bash
docker compose up -d                 # api, worker, postgres, redis, minio, proxy
cd apps/mobile_app && flutter run -d chrome --web-port=5599 \
  --dart-define-from-file=dart_defines.local.json
```

Postgres is on **54329**, Redis on **63799**, MinIO on **9000** (console
9001). `backend/.env` points the CAMARA callbacks and the storage endpoint
at localhost for this; each of those lines is commented with the production
value it must be restored to before deploying.
