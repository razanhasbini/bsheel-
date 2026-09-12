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
  and deletion work locally; only inbound events do not.
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
