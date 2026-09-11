# Turning on AI proof verification

How to go from "the code is there" to "the agent decides submissions", and
why the order matters. Companion to the `AI proof verification (#47)` section
in `CLAUDE.md`, which explains the design; this is the operational sequence.

The short version: **four env flags plus one console toggle make it run, a
sixth switch makes it act, and that last one is earned from a measurement
rather than chosen.**

The console toggle is the one that catches people. `AGENT_SUBMISSION_VERIFICATION_ENABLED=true`
is necessary and **not sufficient**: the agent pipeline also checks an
`app_config` row that migration 0026 seeds `false`, so with the env flag on
and the toggle off every run returns `skipped: 'DISABLED'` and nothing
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
AI_VERIFICATION_ENABLED=false     # default
AGENT_SUBMISSION_VERIFICATION_ENABLED=false
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
AI_VERIFICATION_SHADOW_MODE=true       # default — nothing acts
```

Now the cascade runs for real: forensics on every submission, and a vision
pass on quests whose contract says content can decide. Verdicts, relevance and
observations land on the row, `acted = false`, and **no submission's status
changes**.

This is the state to leave it in. It is also where the money starts: the
cascade is cheap by design (most submissions stop at forensics or the triage
rung) but it is not free.

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
-- What the toggle writes. Check it rather than assuming.
SELECT value FROM app_config WHERE key = 'agent_submission_verification_enabled';
-- '"false"' → the pipeline is skipping every job
```

The agent pipeline now runs too, weighing the three mandatory CAMARA
capabilities alongside the cascade's findings. Shadow mode still holds, so it
records and acts on nothing.

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

## Stage 4 — let it act

Only after `npm run proof:eval` reports a precision you are willing to defend
to a player whose quest it rejects.

```bash
AI_VERIFICATION_SHADOW_MODE=false
```

Then, per category, from the eval's own numbers — **not** as a batch:

```sql
-- Approval authority for one category, once its precision justifies it.
UPDATE quest_verification_defaults
   SET may_auto_approve = true, updated_at = now()
 WHERE category = 'creativity';
```

`may_auto_reject` is seeded `false` for every category deliberately. Telling a
player their proof is fake is the costly error — they carry the appeal — so
that flag is the last one to move and it should move on a precision number for
*that category*, not a global one.

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
| shadow off, before the eval | an unmeasured agent deciding real users' quests |
| `may_auto_reject` on, early | honest players told their proof is fake, with an appeal to spend |
| `CV_PROVIDER=none`, agent on | every submission escalated; the agent knows only that a file exists |
| agent on, `CAMARA_ENABLED=false` | destination quests all escalate — no location evidence to weigh |
| env flag on, console toggle off | silence: every agent job returns `skipped: 'DISABLED'` |

## Turning it off

`AI_VERIFICATION_SHADOW_MODE=true` is the brake, and it stops **both**
verifiers acting. It needs no deploy if your config is environment-driven, and
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
