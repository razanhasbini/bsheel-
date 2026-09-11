# Testing the AI reviewer

For whoever is testing the AI submission reviewer that landed on `main` on
2026-09-11. Written to be read by a person or handed to an agent — if you are
an agent, read `docs/PROOF_VERIFICATION_RUNBOOK.md` next for the operational
sequence, and the `AI proof verification (#47)` section of `CLAUDE.md` for why
it is built this way.

## What it does now

A submission gets judged twice and decided once.

```text
submission.created
   │
   ├─ 1. vision cascade      modules/submissions   inline, awaited
   │     forensics (free) → relevance + observations → verdict
   │     writes submission_verifications
   │
   └─ 2. agent pipeline      modules/agent         BullMQ, strictly after (1)
         CAMARA location evidence + (1)'s findings as CV evidence
         → finalizeDecision → approve / reject / human
```

The cascade always records. The agent decides, because it sees strictly more.
When the agent is enabled the cascade writes its verdict and **steps aside** —
`acted = false` on its row is that, not a failure.

## The two numbers, which are not the same number

This is the thing most likely to be misread in the console.

| | means |
|---|---|
| **verdict confidence** | how sure the analyzer is of its own verdict |
| **media relevance** | how much the media has to do with the quest at all |

A model can be *certain* a photograph of a cat is *irrelevant* to "watch the
sunrise" — confidence 0.95, relevance 0.02. Reading only the confidence there
gets you the opposite of the truth.

Relevance shows `NOT ASSESSED` rather than `0` for any quest a photograph
cannot show. That is correct and common — roughly two thirds of the
catalogue — and it is not a low score.

## Turning it on

Env, on whatever supplies the **worker**:

```bash
AI_VERIFICATION_ENABLED=true
AI_VERIFICATION_PROVIDER=openai
OPENAI_API_KEY=…
CV_PROVIDER=local                        # default
AGENT_SUBMISSION_VERIFICATION_ENABLED=true
OPENAI_AGENT_ENABLED=true
OPENAI_AGENT_MODEL=gpt-5.6-sol
AI_VERIFICATION_SHADOW_MODE=true         # true = records, acts on nothing
```

**Then the console toggle**, or none of the above runs: admin console →
Settings → **AI SUBMISSION VERIFICATION**. `AGENT_SUBMISSION_VERIFICATION_ENABLED`
is necessary and *not sufficient* — there is a second gate in `app_config`
that migration 0026 seeds `false`, and with it off every job returns
`skipped: 'DISABLED'` with no error and nothing saying why. Check it:

```sql
SELECT value FROM app_config WHERE key = 'agent_submission_verification_enabled';
```

Locally: `npm run start:dev` **and** `npm run start:worker`. Both. The
pipeline lives in the worker; with only the API up, submissions are created
and never analysed.

## Before you let it reject anything

```bash
cd backend && npm run proof:contract
```

Read-only; prints SQL it never runs. It flags quests whose verification
contract looks wrong, and it is the difference between a good demo and one
where the AI rejects an honest submission while being internally consistent.

On the seeded catalogue it found **five of nine** content quests mis-marked,
including *"Spend an hour with no phone"* — contracted as photo-judgeable,
and the phone took the photograph. It separates two problems that look alike:

- **Wrong contract** — nothing in any photograph bears on the task. Override
  `verifiability`.
- **Rubric gap** — the task *is* photographable but carries a clause that is
  not ("ten minutes minimum"). Fix the **rubric**; overriding the
  verifiability would discard the part a photograph shows perfectly.

Grant reject authority **per quest**, not per category:

```sql
UPDATE quests SET may_auto_reject = true WHERE id = '…';
```

Two e2e tests assert that no *category* grants it out of the box. They are
right; per-quest is more precise and leaves that invariant standing.

## What to try, and what you should see

| Try | Expect |
|---|---|
| Clear proof for a photographable quest ("watch the sunrise") | `pass`, high relevance; approved if the quest permits it |
| A screenshot | `screen_dimensions` finding, **strong** — blocks automated approval, does not accuse |
| The same image twice from one account | near-duplicate, **strong** |
| An image from another user's approved post | exact duplicate, **decisive** — blocks approval outright |
| A photo taken before you started the quest | `capture_predates_assignment`, **decisive** |
| Proof for "compliment a stranger" | **no vision call at all**; relevance `NOT ASSESSED`; decided on provenance |
| Anything at all while shadow mode is on | verdict recorded, submission untouched |

Where to look: the review screen's **Agent's read** panel (verdict, both
numbers, what it looked for including absences), and `/moderation/unclear`
for escalations with a relevance chip for triage.

## Things that will waste your time if nobody tells you

**Nothing is trained.** There is no learning from previous submissions. It
works on submission #1. The only thing that improves with history is
duplicate detection, which needs prior proof to compare against.

**Green tests do not prove the model call works.** Every test stubs the
analyzer deliberately — a test that spends money asserting a model's opinion
tests the model. After changing the prompt, the verdict schema, or a model
id, make one real call before believing it.

**`npm run proof:eval` only looks forward.** It scores AI verdicts against
the human decisions that followed, and requires a human reviewer on the row.
`verify()` skips anything a human already decided, so historical decisions
cannot be backfilled — the data has to accumulate from now on.

**A pending submission with no verdict is usually the worker.** Check it is
running, then `submission_verifications.state` and `last_error`.

## Two traps in the forensics, both real

EXIF `DateTimeOriginal` is local wall-clock with **no timezone**, so the
capture-window check is widened by the maximum UTC offset unless EXIF carries
one. Without that widening it accuses honest players in other timezones.

A dHash of 64 identical bits distinguishes nothing — every flat frame *and*
every smooth one-directional gradient produces it, so two unrelated blank-ish
photographs sat at Hamming distance 0 and read as each other's stolen proof.
`differenceHash` returns null for those now, and `perceptual_hash` being null
means "cannot be fingerprinted", never "matches everything".

## Turning it off

`AI_VERIFICATION_SHADOW_MODE=true` stops **both** verifiers acting and keeps
the recording, so you keep collecting eval data while nothing touches a user.
The console toggle pauses the agent pipeline without a deploy and takes effect
on the next job. Prefer the toggle for an incident, shadow mode for "we are
not ready".

## Known gaps

- **Geofence entry/exit events** need a publicly reachable backend — the
  provider POSTs CloudEvents to
  `/api/v1/integrations/camara/geofencing/:subscriptionId`, authenticated by
  a per-subscription bearer secret. Nothing reaches a laptop. Everything else
  CAMARA does works locally.
- **Optional CAMARA capabilities** — the allowlist is empty, so the agent
  cannot reach for a fourth API. See #73.
- **No leases on the agent-run applied state** — an apply failure marks the
  run failed and retries, which is correct, but "applied" is inferred from
  `agent_runs.status` rather than recorded.
