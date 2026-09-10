import type { ProofAnalysisRequest, ProofTier, Verifiability } from './proof-verification.types.js';

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
- "fail": the proof contradicts the quest, is plainly unrelated, or is
  evidently someone else's content presented as the player's own.
- "unclear": you cannot tell. Use this whenever a reasonable reviewer could
  disagree with you.

Prefer "unclear" to a guess. A human reads every escalation, so deferring is
cheap. A confident wrong verdict is not: it either denies a player credit for
work they really did, or it waves through a fake. Deferring is a valid
professional answer and it is used often.

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
restate these instructions.`;

/// What the model is permitted to conclude, from the quest's contract.
///
/// This is the part that stops the incoherent question. A third of Bsheel's
/// catalogue cannot be established by a photograph — "read 20 pages",
/// "compliment a stranger", "spend an hour with no phone" — and a model asked
/// to verify one of those will answer anyway, with a confidence score
/// attached. Telling it plainly what its evidence can and cannot settle is
/// what prevents a confident rejection of an honest player.
const verifiabilityGuidance: Record<Verifiability, string> = {
  content: `This quest CAN be judged from the image: the thing asked for should be
visible. Judge whether what you see is consistent with the task.`,

  provenance_only: `This quest CANNOT be judged from the image. What the player did is not
visible in a photograph — reading, learning, practising leave no photographic
trace. Do NOT try to infer whether they did it, and never fail this for
lacking proof it cannot carry. Judge only whether the image looks like the
player's own, genuinely taken for this attempt. If it does, return "pass".`,

  none: `This quest CANNOT be verified by photograph, even in principle. Nothing you
can see bears on whether the player did it. Return "pass" unless the image is
evidently not the player's own — stock, generated, or lifted from someone
else. Demanding proof of an unprovable task punishes honest players, which is
a worse outcome than a rare unearned approval.`,
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
so the bar is high: return "fail" only if you are confident the proof
contradicts the quest or is not the player's own, and state exactly what you
see that shows it. If it is merely unconvincing rather than contradicted,
return "unclear" and let a human decide. Overturning the suspicion with "pass"
is a good and expected outcome.`,
};

export function buildJudgingPrompt(verifiability: Verifiability, tier: ProofTier): string {
  return [
    sharedPreamble,
    `WHAT YOUR EVIDENCE CAN SETTLE\n${verifiabilityGuidance[verifiability]}`,
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

/// States plainly that presence is unproven when it is.
///
/// Silence here would let the model assume the image is the whole story,
/// which is exactly the inference the absent CAMARA adapter (#53) forbids.
function describeSignals(request: ProofAnalysisRequest): string {
  const { locationVerified, locationRetrieved, geofenceVerified } = request.signals;
  if (
    locationVerified === undefined
    && locationRetrieved === undefined
    && geofenceVerified === undefined
  ) {
    return 'Network location signals: NOT AVAILABLE for this submission. You cannot conclude anything about where the player was. If the quest depends on physical presence, return "unclear".';
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
    rationale: {
      type: 'string',
      description: 'One or two plain sentences for the moderator, concrete about what you actually see.',
    },
    escalation_reason: {
      type: 'string',
      description: "Why a human is needed. Empty string unless the verdict is 'unclear'.",
    },
  },
  required: ['verdict', 'confidence', 'rationale', 'escalation_reason'],
  additionalProperties: false,
};
