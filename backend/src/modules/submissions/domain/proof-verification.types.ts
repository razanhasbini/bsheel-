/// AI proof verification (#47).
///
/// A verdict is **advisory**. It never approves a submission and never awards
/// XP — a moderator still decides. See migration 0025 for why, and #53 for the
/// CAMARA signals that are not available yet.

export type ProofVerdict = 'pass' | 'fail' | 'unclear';

export type VerificationState = 'queued' | 'complete' | 'failed' | 'skipped';

/// The three mandatory CAMARA signals (#53).
///
/// Every field is optional, and `undefined` means "not available" — never
/// "the check failed". An absent signal must not read as a negative one, or an
/// unconfigured deployment would silently start failing honest proof.
export interface LocationSignals {
  readonly locationVerified?: boolean;
  readonly locationRetrieved?: boolean;
  readonly geofenceVerified?: boolean;
}

/// Which rung of the cascade a call is on.
///
/// The rungs differ by model, and the models differ ~50x in price, so most
/// submissions must never reach the top one. The asymmetry is deliberate:
/// `triage` may clear a clean submission, but only `reject_review` may
/// conclude that a user's proof is fake.
export type ProofTier = 'triage' | 'deep' | 'reject_review';

/// What the analysis is allowed to conclude about a quest, from the
/// verification contract (migration 0026).
export type Verifiability = 'content' | 'provenance_only' | 'none';

/// What the agent is asked to judge: the quest as specified, and the proof as
/// submitted. Deliberately not the submission row — the analyzer has no
/// business knowing about review state, XP or visibility.
export interface ProofAnalysisRequest {
  readonly questTitle: string;
  readonly questDescription: string;
  readonly questCategory: string;
  /// What a passing photograph looks like for this quest, authored by an
  /// admin. This is what stops the model being asked whether an image proves
  /// something no image could.
  readonly evidenceRubric: string;
  readonly verifiability: Verifiability;
  /// Deterministic provenance findings, already measured. Given to the model
  /// as context so its rationale can account for them, never as a verdict.
  readonly forensicNotes: readonly string[];
  readonly caption: string | null;
  readonly images: readonly ProofImage[];
  /// Media the analyzer cannot inspect — today, video. Named so the verdict
  /// can say which part of the proof went unexamined instead of implying the
  /// whole submission was judged.
  readonly unreadableMedia: readonly string[];
  readonly signals: LocationSignals;
}

export interface ProofImage {
  readonly mediaType: 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp';
  readonly base64: string;
}

export interface ProofAnalysis {
  readonly tier: ProofTier;
  readonly verdict: ProofVerdict;
  /// Null when the model declines to commit to a number, which is itself a
  /// reason to prefer a human.
  readonly confidence: number | null;
  readonly rationale: string;
  readonly escalationReason: string;
  readonly model: string;
  readonly inputTokens: number | null;
  readonly outputTokens: number | null;
}

/// One vision provider, behind one interface.
///
/// The pipeline never names a provider. That is what lets the eval score
/// OpenAI and Anthropic over the same labelled history and pick per category
/// on measured accuracy rather than on taste — and it is why the provider
/// choice is a single config value rather than a rewrite.
export interface ProofAnalyzer {
  readonly enabled: boolean;
  /// Which provider this is, recorded on the verdict so the eval can group by
  /// it.
  readonly provider: 'openai' | 'anthropic';
  analyze(request: ProofAnalysisRequest, tier: ProofTier): Promise<ProofAnalysis>;
}

/// Media types the Messages API accepts as image input. Anything else is
/// reported as unreadable rather than guessed at.
const supportedImageTypes = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp']);

export function isSupportedImageType(contentType: string): boolean {
  return supportedImageTypes.has(contentType.split(';')[0].trim().toLowerCase());
}

/// Collapses a low-confidence decision into an escalation.
///
/// A confident wrong answer and an unconfident right one are not equally
/// costly here: acting on either is a moderator's call, but only the second
/// announces itself. Below the threshold — or with no number at all — the
/// agent defers, which is the behaviour #47 specifies for "unable to verify".
export function applyConfidenceFloor(
  analysis: ProofAnalysis,
  minimumConfidence: number,
): ProofAnalysis {
  if (analysis.verdict === 'unclear') return analysis;
  if (analysis.confidence !== null && analysis.confidence >= minimumConfidence) return analysis;
  const measured = analysis.confidence === null
    ? 'the agent gave no confidence score'
    : `confidence ${analysis.confidence.toFixed(2)} is below the ${minimumConfidence.toFixed(2)} floor`;
  return {
    ...analysis,
    verdict: 'unclear',
    escalationReason: `Downgraded from '${analysis.verdict}': ${measured}.`,
  };
}
