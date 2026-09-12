# Turning on AI proof verification

How to go from "the code is there" to "the agent decides submissions", and
why the order matters. Companion to the `AI proof verification (#47)` section
in `CLAUDE.md`, which explains the design; this is the operational sequence.

> **Read this first: the shipped defaults are already the end state.**
> Every switch below is on out of the box, and migration 0048 sets the
> console toggle to `true`. A fresh deployment with credentials configured
> decides submissions from its first one; without credentials it degrades to
> the human queue. So the stages below are no longer a checklist you work
> through to switch a feature on — they are the map of what each switch
> does, which one to reach for when something is wrong, and how to get back
> to a measurable state. **Stage 4 is where you already are.**
>
> What that costs and what it does not: the rollout was ordered this way so
> nobody would ship an unmeasured agent. The defaults now trade that
> caution for latency, deliberately — a submission carrying a conclusion the
> system already reached should not wait days for a person to reach it
> again. The guards that make it defensible are narrower and still in place
> (a rejection needs positive evidence, `may_auto_reject` is off for the
> categories a photograph cannot settle, integrity findings block automated
> approval). If you want the caution back for a window, that is
> `AI_VERIFICATION_SHADOW_MODE=true`, and it is one variable.

The short version: **four env flags plus one console toggle make it run, and
a sixth switch decides whether it acts. All six now default to on.**

The console toggle is the one that catches people. `AGENT_SUBMISSION_VERIFICATION_ENABLED=true`
is necessary and **not sufficient**: the agent pipeline also checks an
`app_config` row. Migration 0026 seeded it `false` and 0048 set it `true`, so
a database migrated past 0048 has it on — but an operator may have paused it
since, and with it off every run returns `skipped: 'DISABLED'` and nothing
happens. Two switches, deliberately — one is a deploy decision, the other is
an incident brake an admin can pull without one.

Turn it on at **Settings → AI SUBMISSION VERIFICATION** in the admin console
(super_admin only; it is `PUT /api/v1/config/agent_submission_verification_enabled`
underneath).

## What runs where

```text
submission.created
   │
   ├─ 1. vision cascade        modules/submissions   inline, awaited
   │     forensics → relevance + observations → verdict
   │     writes submission_verifications
   │
   └─ 2. agent pipeline        modules/agent         BullMQ, after (1)
         CAMARA evidence + (1)'s findings as CV evidence
         → finalizeDecision → approve / reject / human
```

Two verifiers, one decider. (1) always records. (2) decides when enabled,
and (1) steps aside for it — it sees strictly more evidence.

## Stage 1 — run it blind (no API key needed)

```bash
AI_VERIFICATION_ENABLED=false     # NOT the default any more — both of these
AGENT_SUBMISSION_VERIFICATION_ENABLED=false   # must now be set explicitly
```

Nothing analyses anything, but every submission still gets a
`submission_verifications` row from the `submission.created` consumer. That is
deliberate: turning the feature on later can find everything it never looked
at, via `npm run proof:eval`'s sibling, the sweep.

Worth confirming before going further:

```sql
SELECT state, count(*) FROM submission_verifications GROUP BY state;
-- expect: queued | <number of submissions>
```

## Stage 2 — give it eyes, let it decide nothing

```bash
AI_VERIFICATION_ENABLED=true
AI_VERIFICATION_PROVIDER=openai        # or anthropic
OPENAI_API_KEY=sk-…                    # required; boot refuses without it
CV_PROVIDER=local                      # default
AI_VERIFICATION_SHADOW_MODE=true       # explicit: nothing acts (default is false)
```

Now the cascade runs for real: forensics on every submission, and a vision
pass on quests whose contract says content can decide. Verdicts, relevance and
observations land on the row, `acted = false`, and **no submission's status
changes**.

This used to be the state to leave it in, and it is still the state to
return to when you want a clean eval slice — `acted = false` is only honest
data while nothing acted. It is also where the money starts: the cascade is
cheap by design (most submissions stop at forensics or the triage rung) but
it is not free.

**How to watch it:**

- `/moderation/unclear` in the admin console — escalations, with a relevance
  chip for triage and a sidebar badge.
- The review screen's **Agent's read** panel — verdict, verdict confidence,
  media relevance, and what it looked for, on every submission it judged.
- `npm run proof:eval` — precision against the human decisions that followed.

```sql
-- Is it actually looking? (models cost money; zeros mean it is not)
SELECT stage, count(*), round(avg(confidence)::numeric, 2) AS conf,
       round(avg(relevance)::numeric, 2) AS relev
FROM submission_verifications WHERE state = 'complete' GROUP BY stage;
```

## Stage 3 — add the network, for destination quests only

```bash
CAMARA_ENABLED=true
CAMARA_API_KEY=…                  # boot refuses without it
AGENT_SUBMISSION_VERIFICATION_ENABLED=true
OPENAI_AGENT_ENABLED=true
OPENAI_AGENT_MODEL=…              # boot refuses without it, and without OPENAI_API_KEY
```

**Then flip the console toggle** (Settings → AI SUBMISSION VERIFICATION), or
none of this runs:

```sql
-- What the toggle writes. Check it rather than assuming. Migration 0048
-- sets it true, so '"false"' here means a person paused it.
SELECT value FROM app_config WHERE key = 'agent_submission_verification_enabled';
-- '"false"' → the pipeline is skipping every job
```

The agent pipeline now runs too, weighing the three mandatory CAMARA
capabilities alongside the cascade's findings. Whether it *acts* on what it
concludes is the one remaining switch, Stage 4 — which is on by default, so
unless you set `AI_VERIFICATION_SHADOW_MODE=true` you are there already.

```sql
-- Did the agent actually run, and what did it conclude?
SELECT status, output->>'decision' AS decision, count(*)
FROM agent_runs WHERE kind = 'submission_verification'
GROUP BY status, decision ORDER BY count DESC;
```

Two things will not work on a laptop, and that is the network's fault rather
than the code's:

- **Geofence entry/exit events** arrive as CloudEvents POSTed by the provider
  to a public webhook. Set `CAMARA_GEOFENCING_SINK_BASE_URL` to a deployed
  backend or `GEOFENCING` evidence stays `UNAVAILABLE` — which routes to a
  human, correctly.
- **Number Verification** needs the user's own verified device.

See `docs/CAMARA_TESTING.md` for the live demo surface and the four-outcome
matrix.

## Before Stage 4 — audit the catalogue

```bash
cd backend && npm run proof:contract          # read-only
cd backend && npm run proof:contract -- --sql # with the fixes
```

Migration 0034 sets the contract per *category*, and says in its own comment
that a category default cannot be right for every quest in it: "Watch the
sunrise" and "Spend an hour with no phone" are both `adventure`, and only one
is checkable from a photograph. Per-quest overrides exist for the other kind,
and nothing makes anyone author them — on the seeded catalogue, **five of nine
content quests were mis-marked and none had an override**.

This matters the moment `may_auto_reject` is granted to a category: the agent
is asked whether a photograph proves something no photograph can, answers
anyway with a confidence score, and rejects an honest player. The failure
arrives through the catalogue rather than through the code, which is why no
test catches it.

The audit separates two problems that look alike and need different fixes:

| | Example | Fix |
|---|---|---|
| **Wrong contract** — nothing in any photograph bears on the task | "Spend an hour with no phone" | override `verifiability` |
| **Rubric gap** — the task *is* photographable but carries a clause that is not | "Draw the view from your window — ten minutes minimum" | amend the rubric, **not** the verifiability |

Overriding the second kind would discard the part a photograph does show. It
wants a rubric that tells the model to ignore the clause, the way the seeded
`fitness` rubric already does: *"Counts and durations CANNOT be verified from
an image — never reject for failing to show a count."*

It is a keyword check, so read the full table it prints rather than only the
flags — particularly any row where `reject` is already true.

## Scoring it without waiting

```bash
npm run build                                  # the backfill runs against dist/
npm run proof:backfill                         # dry run: what it would score, and the cost
npm run proof:backfill -- --apply --limit 25
npm run proof:eval
```

`proof:eval` needs verdicts paired with the human decision that followed, and
`verify()` refuses to analyse anything already reviewed — correctly, since a
vision call on a settled submission buys nothing operationally. So the
ordinary path only accumulates forward, and a deployment with a year of
moderation history still has to sit in shadow mode for weeks before it can
answer "is this good enough yet".

The backfill reads that history. Same forensics, same cascade, same policy;
the verdict recorded is the one the agent *would* have reached on a submission
whose outcome a person settled before the verdict existed — which makes it
cleaner eval data than shadow mode rather than dirtier, since it cannot have
influenced the decision it is scored against even in principle.

Three things it will not do, which is what makes it safe to point at a
production database:

- **never acts** — there is no `act()` call on that path at any setting
- **never claims** — no attempt increment, no state change, so it cannot
  consume the retries a live submission needs, and it is re-runnable
- **never alerts** — `complete()` notifies every admin on an escalation;
  scoring a year of history through it would notify them about every old
  submission the agent found ambiguous

It selects only submissions where `reviewed_by IS NOT NULL`. Both automated
deciders pass a null actor deliberately, so that is what separates ground
truth from the agent marking its own homework.

It spends real vision calls, one submission at a time — hence the limit, and
the dry run being the default. Quests whose contract is `provenance_only` or
`none` make no vision call at all, and the dry run tells you how many of each
you have before you spend anything.

## Stage 4 — let it act (the default)

```bash
AI_VERIFICATION_SHADOW_MODE=false   # the default; set it to true to stop acting
```

This is where a current deployment starts. The eval has not stopped being
the right instrument — run `npm run proof:eval` against whatever slice you
have (the backfill above produces one without waiting) and keep watching the
precision, because the question "would I defend this to a player whose quest
it rejected" is still the question. What changed is only which way the
default answers it while nobody is looking.

Then, per category, from the eval's own numbers — **not** as a batch:

```sql
-- Approval authority for one category, once its precision justifies it.
UPDATE quest_verification_defaults
   SET may_auto_approve = true, updated_at = now()
 WHERE category = 'creativity';
```

`may_auto_reject` was seeded `false` for every category in 0034; migration
0046 turned it on for the `content`-verifiable ones, where the absence of the
asked-for thing is a finding the media actually supports. It stays `false`
for `provenance_only` and `none`, and that is not an oversight to tidy up:
telling a player their proof is fake is the costly error — they carry the
appeal — and on those categories a rejection could only be an accusation
about the file. Move a per-quest override on a precision number for *that*
kind of quest, not a global one.

A per-quest override beats the category default, which is how the awkward
quests get handled:

```sql
-- "Spend an hour with no phone" is adventure, and no photograph can show it.
UPDATE quests
   SET verifiability = 'none', may_auto_approve = true
 WHERE id = '…';
```

## The order is not arbitrary

| If you skip to | You get |
|---|---|
| shadow off (the default), with no eval ever run | an unmeasured agent deciding real users' quests — the risk the defaults accept, and the reason to run `proof:backfill` + `proof:eval` early on a new deployment |
| `may_auto_reject` on, early | honest players told their proof is fake, with an appeal to spend |
| `CV_PROVIDER=none`, agent on | every submission escalated; the agent knows only that a file exists |
| agent on, `CAMARA_ENABLED=false` | destination quests all escalate — no location evidence to weigh |
| env flag on, console toggle off | silence: every agent job returns `skipped: 'DISABLED'` |

## Turning it off

`AI_VERIFICATION_SHADOW_MODE=true` is the brake — a change from the default
now, not a confirmation of it — and it stops **both** verifiers acting. It needs no deploy if your config is environment-driven, and
it leaves the recording intact — so you keep collecting eval data while
nothing touches a user.

The console toggle (Settings → AI SUBMISSION VERIFICATION) pauses the agent
pipeline without a deploy, and takes effect on the very next job — it is read
fresh per job rather than cached. It does **not** stop the #47 cascade, which
keeps recording. Prefer the toggle for an incident; prefer shadow mode when
the decision is "we are not ready to act yet".

## Cost, roughly

The cascade's rungs differ ~50× in price and most submissions never reach the
top one. Per submission:

| Stage | Cost |
|---|---|
| forensics | none — no model |
| triage (`detail: low`) | cheapest tier, ~1 image |
| deep | mid tier, `detail: high`, only where triage could not tell |
| reject_review | top tier, **only before a rejection** |

Quests whose contract is `provenance_only` or `none` make **no vision call at
all**. That is roughly two thirds of the catalogue, and it is the single
largest cost decision in the design.
