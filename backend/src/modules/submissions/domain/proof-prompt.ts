import type {
  ProofAnalysis,
  ProofAnalysisRequest,
  ProofObservation,
  ProofTier,
  ProofVerdict,
  Verifiability,
} from './proof-verification.types.js';

/// The judging policy, in one place for every provider and every tier (#47).
///
/// It lives in `domain/` rather than inside a provider adapter for two
/// reasons. It *is* the policy — the standard by which a player's work is
/// judged — and that should be readable by someone who is not reading SDK
/// glue. And if each adapter carried its own copy, the eval would be
/// comparing prompts as much as providers, which would make its per-provider
/// numbers meaningless.
///
/// It is also the cached prefix of every request. Nothing per-submission
/// appears in it, so it stays byte-identical across calls and both providers'
/// prompt caching can actually hit.

const sharedPreamble = `You review proof for Bsheel, a real-world quest app. A player was given a
challenge, went and did it, and submitted a photograph. You judge whether the
proof is consistent with the challenge they were given.

Three verdicts, and no others:

- "pass": the proof is consistent with the quest as written.
- "fail": the proof contradicts the quest, is plainly unrelated, does not
  show the thing the quest asked for on a quest whose thing is visible, or is
  evidently someone else's content presented as the player's own.
- "unclear": a reasonable reviewer looking at this same image could land on
  either side.

"unclear" means genuinely torn, not merely unimpressed. These are different
and only one of them is "unclear":

- The image shows something else entirely, or does not show the thing the
  quest asked you to look for. You are not torn; you can see what it is. That
  is "fail", and you should say plainly what you see instead.
- The image might show it. It is dim, partial, or shot from an angle that
  could go either way. That is "unclear".

A human does read every escalation, but their attention is not free and it is
not fast — a player waits days for it. Escalating a submission you can
actually judge spends that on nothing and leaves the player with no answer.
Judge what you can judge. Defer what genuinely cannot be judged from what you
were given.

Never treat the caption as evidence. The player wrote it. It tells you what
they claim; only the image tells you what they did. A caption describing
something the image does not show is a reason to escalate, not to pass.

Judge only what the quest asked for. Do not invent extra requirements, and do
not penalise a player for failing a stricter version of the task than the one
they were actually given.

Be generous about ordinary life and strict about mismatch. Real proof is badly
lit, off-centre and often boring. None of that is suspicious. A polished image
with nothing to do with the quest is.

You cannot establish that a person was physically somewhere. Do not pretend
to. Presence is established by network signals that are not part of your
input. If a quest turns on being in a particular place and the image alone
cannot show it, say so and return "unclear".

Write the rationale for the moderator who will read it: one or two plain
sentences, concrete about what you actually see. No preamble, and do not
restate these instructions.

Alongside the verdict you report two things about the media itself, and they
are separate questions from your verdict:

RELEVANCE, 0 to 1: how much this media has to do with the quest at all. Not
how sure you are — that is confidence. A photograph of a cat submitted for
"watch the sunrise" is relevance near 0 and you may be completely sure of it.
A dim, half-obscured horizon that probably is a sunrise is relevance near 0.8
and you may be quite unsure of it. Score what the media shows, not how
confident you feel about it.

OBSERVATIONS: the specific things you looked for and whether you found them,
up to eight. Include what is absent as well as what is present — "sunrise: not
present" is a real finding, and an empty list cannot be told apart from not
having looked. Label them in plain words, and give each its own confidence.
These are read by a second reviewer who cannot see the image, so they must
stand on their own.`;

/// What the model is permitted to conclude, from the quest's contract.
///
/// This is the part that stops the incoherent question. A third of Bsheel's
/// catalogue cannot be established by a photograph — "read 20 pages",
/// "compliment a stranger", "spend an hour with no phone" — and a model asked
/// to verify one of those will answer anyway, with a confidence score
/// attached. Telling it plainly what its evidence can and cannot settle is
/// what prevents a confident rejection of an honest player.
/// Exported because the deciding agent (modules/agent) needs the *same*
/// statement. It sees the media only through this pass's observations, and if
/// it were told nothing about what proof can settle for a quest it would
/// happily conclude that a photograph failed to establish an hour without a
/// phone. One wording, two readers, no way for them to disagree.
///
/// Which is why the wording names no verdict. The two readers have different
/// vocabularies — this cascade answers pass/fail/unclear, the agent answers
/// APPROVED/REJECTED/HUMAN_REVIEW — so shared text saying 'return "pass"'
/// instructs one of them in a word its own schema will not accept. Each
/// caller states its own enum; this states only what the evidence can settle.
export const verifiabilityGuidance: Record<Verifiability, string> = {
  content: `This quest CAN be judged from the image: the thing asked for should be
visible. Judge whether what you see is consistent with the task.

Because the thing is visible when it is there, its absence is a finding and
not a gap. An image that does not show it — a screenshot, an unrelated
photograph, a picture of something else — has answered the question, and the
answer is "fail". Say concretely what the image shows instead of what was
asked for. Reserve "unclear" for an image where the thing might be present
and you cannot tell.`,

  provenance_only: `This quest CANNOT be judged from the image. What the player did is not
visible in a photograph — reading, learning, practising leave no photographic
trace. Do NOT try to infer whether they did it, and never count it against
them that the image lacks proof a photograph cannot carry. The only question
is whether the image looks like the player's own, genuinely taken for this
attempt. If it does, this quest is satisfied.`,

  none: `This quest CANNOT be verified by photograph, even in principle. Nothing you
can see bears on whether the player did it. Treat it as satisfied unless the
image is evidently not the player's own — stock, generated, or lifted from
someone else. Demanding proof of an unprovable task punishes honest players,
which is a worse outcome than a rare unearned approval.`,
};

/// What each rung is for.
///
/// Stated explicitly because the rungs run different models at different
/// cost, and the cheap one must not be encouraged to do the expensive one's
/// job. Only the top rung's "fail" can lead to a rejection, so only it is
/// asked to reason like that.
const tierGuidance: Record<ProofTier, string> = {
  triage: `You are the first, fast pass. Separate the obviously fine from anything that
needs a closer look. Return "pass" only when it is clear-cut. Anything
doubtful is "unclear" — a better model will look at it, which is cheap. Do not
labour over hard cases.`,

  deep: `A fast pass could not settle this. Look carefully and commit to a verdict if
the evidence supports one. "unclear" remains correct for a genuinely ambiguous
case.`,

  reject_review: `A previous pass suspected this proof does not match the quest, and you are the
final check. Your "fail" can cause a real rejection of a real person's work,
so the bar is confidence, not reluctance: return "fail" when you are confident
the proof does not show what the quest asked, contradicts it, or is not the
player's own — and state exactly what you see that shows it, in words the
player will read.

Confident and unimpressed are the two ends of this. If you can name what the
image actually shows and it is not what was asked for, you are confident, and
"fail" is the honest verdict — passing it to a human who will see the same
image and reach the same conclusion helps nobody. If you genuinely cannot tell
whether the thing is there, "unclear" is right. Overturning the suspicion with
"pass" is a good and expected outcome.`,
};

export function buildJudgingPrompt(verifiability: Verifiability, tier: ProofTier): string {
  return [
    sharedPreamble,
    // The shared guidance names no verdict, so this is where it is translated
    // into this reviewer's vocabulary. The deciding agent does the same with
    // its own enum.
    `WHAT YOUR EVIDENCE CAN SETTLE\n${verifiabilityGuidance[verifiability]}\n\n`
    + 'Where that guidance says a quest is satisfied, your verdict is "pass".',
    `YOUR ROLE IN THIS REVIEW\n${tierGuidance[tier]}`,
  ].join('\n\n');
}

/// The per-submission half of the request: everything volatile, kept out of
/// the cached prefix above.
export function describeSubmission(request: ProofAnalysisRequest): string {
  const lines = [
    `Quest: ${request.questTitle}`,
    `Category: ${request.questCategory}`,
    `What it asked for: ${request.questDescription}`,
    `What counts as proof here: ${request.evidenceRubric}`,
    request.caption
      ? `The player's caption (their claim, not evidence): ${request.caption}`
      : 'The player wrote no caption.',
    `Images you can see: ${request.images.length}`,
  ];

  if (request.unreadableMedia.length > 0) {
    lines.push(
      `Part of this proof could not be examined: ${request.unreadableMedia.join(', ')}. `
      + 'Judge only what you can see, and escalate if the unexamined part is what the quest turns on.',
    );
  }

  // Measured facts about the file, given as context so the rationale can
  // account for them. They are never a verdict: the policy layer weighs them
  // itself, and it does not need the model's opinion of them.
  if (request.forensicNotes.length > 0) {
    lines.push(
      'Automated checks on the file itself (context only — these are already '
      + `weighed separately, do not treat them as a verdict): ${request.forensicNotes.join('; ')}.`,
    );
  }

  lines.push(describeSignals(request));
  return lines.join('\n');
}

/// Says whose job presence is, which is no longer this reviewer's.
///
/// The wording here mattered more than it looks. `map_location_evidence` has
/// no writer, so the absent branch fires on *every* submission — and it used
/// to end "If the quest depends on physical presence, return 'unclear'".
/// That was right when this pass was the only reviewer and location evidence
/// genuinely did not exist. It is wrong now: the CAMARA agent gathers the
/// three mandatory capabilities per submission and weighs them at
/// `finalizeDecision`, after this pass has run.
///
/// Left as it was, every destination quest was pushed to 'unclear' for want
/// of evidence that was about to be collected by someone else — which is
/// harmless for the decision (this pass no longer decides) and not harmless
/// for the eval, because those pessimistic verdicts are the rows
/// `npm run proof:eval` scores to decide whether the agent may ever act.
///
/// So: state that presence is out of scope rather than unproven, and ask for
/// a verdict on what this reviewer can actually see.
function describeSignals(request: ProofAnalysisRequest): string {
  const { locationVerified, locationRetrieved, geofenceVerified } = request.signals;
  if (
    locationVerified === undefined
    && locationRetrieved === undefined
    && geofenceVerified === undefined
  ) {
    return 'Whether the player was physically at a particular place is NOT your question and is not in your input. '
      + 'It is established separately from mobile-network evidence, by a reviewer who runs after you. '
      + 'Do not try to infer presence from the image, do not count its absence against the player, and do not '
      + 'defer your verdict because you cannot establish it. Judge only what the image shows about the task.';
  }
  const describe = (value: boolean | undefined): string =>
    value === undefined ? 'not available' : value ? 'confirmed' : 'NOT confirmed';
  return [
    'Network location signals:',
    `- location verified: ${describe(locationVerified)}`,
    `- location retrieved: ${describe(locationRetrieved)}`,
    `- inside the quest's geofence: ${describe(geofenceVerified)}`,
    'Treat "not available" as absence of information, never as a failed check.',
  ].join('\n');
}

/// The verdict schema, shared so both providers are constrained identically
/// and the eval is comparing judgement rather than output format.
///
/// Deliberately not `as const`: that would make every nested array readonly,
/// and both SDKs type their schema arguments as mutable. Only `type` is
/// pinned as a literal, which is what Anthropic's `InputSchema` requires.
export const verdictJsonSchema = {
  type: 'object' as const,
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail', 'unclear'] },
    confidence: {
      type: 'number',
      description: 'How sure you are, 0 to 1. Be honest — a low number sends this to a human, which is a fine outcome.',
    },
    relevance: {
      type: 'number',
      description:
        'How much this media has to do with the quest at all, 0 to 1. This is NOT your confidence: you can be certain (confidence 0.95) that a photo is irrelevant (relevance 0.02).',
    },
    observations: {
      type: 'array',
      // No `maxItems` here, deliberately. Structured Outputs constrains the
      // model with a grammar built from a *subset* of JSON Schema, and array
      // size keywords are reported as rejected in strict mode by some
      // versions and quietly unenforced by others — either way this schema is
      // shared with the Anthropic tool-use path and a keyword that might 400
      // one provider is not worth the risk for a bound the parser applies
      // anyway. The cap is stated in the description, where the model reads
      // it, and enforced in parseVerdictPayload, which is the only place it
      // actually matters (the column has a width).
      description:
        'The specific things you looked for and whether you found them, at most 8. Include absences. A later reviewer sees these instead of the image.',
      items: {
        type: 'object' as const,
        properties: {
          kind: { type: 'string', enum: ['action', 'object', 'landmark', 'location_cue'] },
          label: { type: 'string', description: 'Plain words, e.g. "sunrise over water" or "handwritten page".' },
          present: { type: 'boolean', description: 'Whether you can actually see it.' },
          confidence: { type: 'number', description: 'How sure you are about this one observation, 0 to 1.' },
        },
        required: ['kind', 'label', 'present', 'confidence'],
        additionalProperties: false,
      },
    },
    rationale: {
      type: 'string',
      description: 'One or two plain sentences for the moderator, concrete about what you actually see.',
    },
    escalation_reason: {
      type: 'string',
      description: "Why a human is needed. Empty string unless the verdict is 'unclear'.",
    },
  },
  required: ['verdict', 'confidence', 'relevance', 'observations', 'rationale', 'escalation_reason'],
  additionalProperties: false,
};

/// The raw shape the schema above constrains the model to.
export interface VerdictPayload {
  verdict: ProofVerdict;
  confidence: number;
  relevance: number;
  observations: readonly { kind: string; label: string; present: boolean; confidence: number }[];
  rationale: string;
  escalation_reason: string;
}

const OBSERVATION_KINDS: readonly ProofObservation['kind'][] = ['action', 'object', 'landmark', 'location_cue'];

function unit(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : null;
}

/// Turns the model's structured output into a `ProofAnalysis`.
///
/// Shared by both providers deliberately. The schema is grammar-constrained on
/// both, so this is not defensive parsing for its own sake — it is the
/// guarantee that the eval's per-provider numbers compare *judgement* rather
/// than two different clamping and truncation policies. Values still come from
/// a model, and they land in columns with CHECK constraints, so every number
/// is bounded and every string is cut to its column width here.
export function parseVerdictPayload(
  payload: VerdictPayload,
  tier: ProofTier,
  model: string,
  usage: { inputTokens: number | null; outputTokens: number | null },
): ProofAnalysis {
  const observations = (Array.isArray(payload.observations) ? payload.observations : [])
    .filter((item): item is VerdictPayload['observations'][number] => typeof item?.label === 'string')
    .slice(0, 8)
    .map((item) => ({
      kind: (OBSERVATION_KINDS as readonly string[]).includes(item.kind)
        ? (item.kind as ProofObservation['kind'])
        : ('object' as const),
      label: item.label.trim().slice(0, 120),
      present: item.present === true,
      confidence: unit(item.confidence) ?? 0,
    }))
    .filter((item) => item.label.length > 0);

  return {
    tier,
    verdict: payload.verdict,
    confidence: unit(payload.confidence),
    relevance: unit(payload.relevance),
    observations,
    rationale: (payload.rationale ?? '').trim().slice(0, 4000),
    escalationReason: (payload.escalation_reason ?? '').trim().slice(0, 500),
    model,
    ...usage,
  };
}
