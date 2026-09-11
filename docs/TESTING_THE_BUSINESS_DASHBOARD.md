# Testing the business dashboard

For whoever is testing business accounts (#14) and the partner analytics
dashboard (#50), which landed on `main` on 2026-09-11. Written to be read by
a person or handed to an agent. For *why* it is built this way, read the
`Business / destination accounts (#14)` section of `CLAUDE.md`; for
deployment, `docs/DEPLOYMENT.md`.

## What exists

```text
apps/mobile_app        a card on the owner's OWN profile, and nothing else
   │                   (business accounts change nothing else about the app)
   └─ link ──────────► apps/business_web   served at admin.bsheel.app/business
                          summary · daily · quests · places · countries
                          proof · team
```

Three tables carry it: `businesses`, `business_places` (which real locations
it speaks for) and `business_members` (`owner` / `manager`).

## Start here: nothing works until a business exists

A business needs **four** things, and the fourth is the one that gets
forgotten because it is NULL by default and is *not* implied by the business
existing:

1. the business
2. the places it speaks for
3. the owner as a member
4. the **analytics subscription**

One command does all four, through the audited admin endpoints:

```bash
cd backend
npm run business:provision -- \
  --api https://api.bsheel.app/api/v1 \
  --admin-email you@example.com --admin-password '...' \
  --name 'Tawlet Beirut' --owner theirusername \
  --place 'Mar Mikhael'
```

It is a **dry run** until you add `--apply`. It resolves the owner and the
places *before* writing anything, so a mistyped handle leaves nothing behind
rather than a business nobody can manage. `--no-subscribe` deliberately skips
step 4 — use it to see the refusal, not for a real account.

Places must already exist and be published (admin console → Destinations).
The script will tell you if one does not.

## The five things worth actually checking

### 1. The app is unchanged for everyone else

Sign in as any ordinary user. There should be **no** business card on their
profile, nothing on the feed, nothing on the map. If you see a business
anything as a non-member, that is a bug worth stopping for.

### 2. The owner sees a card, and only on their own profile

As the owner, their own profile carries one card naming the business and
linking to the dashboard. Open **someone else's** profile as the owner, and
open the owner's profile **as someone else** — neither shows it. A business
account is not public information here.

If the card says *"this build was not told where the dashboard lives"*, the
build was made without `DASHBOARD_URL`. That is the build's fault, not the
account's — see `dart_defines.release.json`.

### 3. The refusals are three different messages

Each has a different cause and a different fix, so each says something
different. Worth exercising all three, because collapsing them is the easy
mistake:

| Do this | Expect |
|---|---|
| `PATCH admin/businesses/:id {"status":"suspended"}` | "account is suspended, your claimed places are kept" — and `403 BUSINESS_SUSPENDED` on every analytics route |
| provision with `--no-subscribe` | "analytics is not part of this account yet" — and `403 ANALYTICS_NOT_SUBSCRIBED` |
| sign in as a non-member | the dashboard explains it; it does **not** bounce you to login |

Suspension outranks the subscription: a suspended account reports the
suspension even if it is also unsubscribed, because telling an owner to buy
analytics they already have is worse than saying nothing.

### 4. A business sees its own places and nobody else's

The strongest check. Provision **two** businesses at **two** places, put an
approved submission at each, and confirm each dashboard reports only its own.
There is no place-id parameter anywhere in the analytics API — the place set
comes from membership — so if one business can see the other's numbers,
something has gone badly wrong.

Also try `?business=<the other business's id>` on the dashboard URL. It
should quietly fall back to your own, not attempt a read the server would
refuse.

### 5. The numbers say what they mean

These are the ones a reader can misread, so they are worded deliberately:

- **"Visitors" counts people, not completions.** One person finishing three
  quests at your place is one visitor.
- **A quest nobody has started shows `—`, not `0%`.** Zero would rank an
  untested quest as the worst performer.
- **"Started" includes people who never submitted.** That is the point of the
  rate; counting submissions would report perfect follow-through.
- **The country panel states its denominator** — *"Based on 5 of 40
  visitors"*. A share of the disclosed population is not a share of your
  visitors.
- **A place claimed but not published says so.** It reports no activity at
  all, which otherwise looks like a broken dashboard.

## Two things that will look broken and are not

**The country panel is empty.** It only counts visitors who have *both* set
a country (profile → where you are from) and turned analytics on. Nobody has
by default. It will say *"None of your N visitors have shared a country
yet"* — which is the honest answer, not zero visitors. To see it populated,
set a country and consent on a few accounts that have completed a quest at
the place.

**Private proof is missing from the proof wall, on purpose.** It shows only
proof its author published to the feed (`show_in_feed`). An approved
submission the author kept private still counts as a completion and its
media is never shown. Both facts at once is correct: the visit happened, the
bytes stay theirs.

## If the dashboard is not deployed yet

The mobile card's button opens `https://admin.bsheel.app/business/?business=<id>`
and will 404 until the bundle is served there. Everything else works — the
card itself, the API, and running the dashboard locally against production.

Worth knowing when it *is* deployed: that link needs no SPA fallback,
because `?business=<id>` is a query string. Only a deep path
(`/business/login`) does. See `docs/DEPLOYMENT.md` for the checked table.

## Running it locally

```bash
cd backend && npm run start:dev          # API on :3010
cd apps/business_web && flutter run -d chrome \
  --dart-define=API_URL=http://127.0.0.1:3010/api/v1
```

Sign in with an ordinary Bsheel account that is a business member. There is
no separate partner account.

## If you are an agent

The invariants worth not breaking, each with a test that fails if you do:

- `business` is **not** a system role — `test/business.spec.ts`
- a non-member gets **404, not 403** (403 confirms the business exists and
  turns id enumeration into a directory) — `test/business-accounts.e2e-spec.ts`
- a place has **at most one owner**, enforced by a UNIQUE constraint
- the proof query uses the **feed's exact predicate**, because `media_url` is
  an object key and `POST /media/sign` does not re-check the viewer — so the
  key *is* the access
- cohorts below 5 are **suppressed but counted**, so the figures reconcile
- the chart uses **explicit pixel heights**, never `FractionallySizedBox` — a
  Row hands it an infinite height and it throws, which crashed the chart for
  any business with data
