import { z } from 'zod';

// Contracts for the AI agent phase. These are internal (agent <-> backend,
// backend <-> CV service) rather than HTTP DTOs, so Zod owns validation here
// the same way it already owns config/environment.ts — class-validator stays
// the convention for anything presentation/ exposes over HTTP.

export const AgentRunKindSchema = z.enum([
  'quest_time_estimation',
  'xp_recommendation',
  'submission_verification',
]);
export type AgentRunKind = z.infer<typeof AgentRunKindSchema>;

const Confidence = z.number().min(0).max(1);
const MediaType = z.enum(['image', 'video', 'mixed']);

export const CoordinatesSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracyMeters: z.number().nonnegative().optional(),
});
export type Coordinates = z.infer<typeof CoordinatesSchema>;

// Deterministic bounds computed by the backend (verification-policy.ts) from
// the quest's own base XP/duration. The model sees them so it can reason
// about scale, but they are enforced by clampDurationMinutes/clampXp
// regardless of what the model outputs — never taken from the model itself.
export const AgentPolicySchema = z
  .object({
    minDurationMinutes: z.number().int().positive(),
    maxDurationMinutes: z.number().int().positive(),
    minXp: z.number().int().nonnegative(),
    maxXp: z.number().int().nonnegative(),
    approveThreshold: Confidence,
    rejectThreshold: Confidence,
  })
  .strict();
export type AgentPolicy = z.infer<typeof AgentPolicySchema>;

export const AgentContextSchema = z
  .object({
    runId: z.string().uuid(),
    task: AgentRunKindSchema,
    user: z
      .object({
        // Deliberately just the id — no name, email or phone reaches the model.
        id: z.string().uuid(),
      })
      .strict(),
    quest: z
      .object({
        id: z.string().uuid(),
        title: z.string(),
        description: z.string(),
        category: z.string(),
        difficulty: z.string(),
        baseXp: z.number().int().nonnegative(),
        defaultDurationHours: z.number().positive(),
        stageCount: z.number().int().positive().default(1),
        // The resolved verification contract (#47, migration 0034): what proof
        // can establish for this quest, and what the agent is allowed to do
        // about it. Not optional, because a missing contract is the one case
        // that must fail closed — the view itself COALESCEs an unknown
        // category to none/no-authority rather than leaving it null.
        verification: z
          .object({
            verifiability: z.enum(['content', 'provenance_only', 'none']),
            evidenceRubric: z.string(),
            mayAutoApprove: z.boolean(),
            mayAutoReject: z.boolean(),
          })
          .strict(),
        requirements: z
          .object({
            actions: z.array(z.string()),
            objects: z.array(z.string()),
            requiredPeople: z.number().int().positive(),
            requiredItems: z.array(z.string()),
            acceptedMedia: z.array(MediaType),
          })
          .strict()
          .optional(),
        destination: z
          .object({
            placeId: z.string().uuid(),
            countryCode: z.string().length(2),
            coordinates: CoordinatesSchema,
            radiusMeters: z.number().positive(),
            requiresVerification: z.boolean(),
          })
          .strict()
          .optional(),
        eventContext: z
          .object({
            sponsorName: z.string().optional(),
            availableFrom: z.string().datetime().optional(),
            availableUntil: z.string().datetime().optional(),
          })
          .strict()
          .optional(),
      })
      .strict(),
    assignment: z
      .object({
        userQuestId: z.string().uuid(),
        assignedAt: z.string().datetime(),
        expiresAt: z.string().datetime(),
        submittedAt: z.string().datetime().optional(),
      })
      .strict()
      .optional(),
    submission: z
      .object({
        id: z.string().uuid(),
        mediaType: MediaType,
        mediaCount: z.number().int().min(1).max(10),
        caption: z.string().nullable(),
      })
      .strict()
      .optional(),
    collaboration: z
      .object({
        mode: z.enum(['solo', 'with', 'versus']),
        participantCount: z.number().int().positive(),
      })
      .strict(),
    policy: AgentPolicySchema,
  })
  .strict();
export type AgentContext = z.infer<typeof AgentContextSchema>;

export const QuestTimeRecommendationSchema = z
  .object({
    recommendedMinutes: z.number().int().positive(),
    confidence: Confidence,
    factors: z
      .array(
        z.object({
          code: z.string(),
          adjustmentMinutes: z.number().int(),
          rationale: z.string(),
        }),
      )
      .max(10),
    assumptions: z.array(z.string()).max(5),
  })
  .strict();
export type QuestTimeRecommendation = z.infer<typeof QuestTimeRecommendationSchema>;

export const XpRecommendationSchema = z
  .object({
    recommendedXp: z.number().int().nonnegative(),
    confidence: Confidence,
    factors: z
      .array(
        z.object({
          code: z.string(),
          adjustmentXp: z.number().int(),
          rationale: z.string(),
        }),
      )
      .max(10),
    assumptions: z.array(z.string()).max(5),
  })
  .strict();
export type XpRecommendation = z.infer<typeof XpRecommendationSchema>;

// The exact contract src/integrations/computer-vision adapters must satisfy,
// and the one a third-party CV engineer's service must return (see
// http-cv-evidence.provider.ts). status distinguishes "unavailable/failed"
// from "ran cleanly and detected nothing" — a fail-closed adapter must never
// claim AVAILABLE.
export const CvEvidenceSchema = z
  .object({
    status: z.enum(['AVAILABLE', 'UNAVAILABLE', 'FAILED']),
    provider: z.string(),
    modelVersion: z.string(),
    analyzedAt: z.string().datetime(),
    // How much the submitted media has to do with the quest, 0..1. Optional
    // because it is meaningful only for quests a photograph can actually show
    // — see CvEvidenceAnalysisInput.task.verifiability. Absent means "not
    // assessed", which is the correct answer for two thirds of the catalogue
    // and must never be read as "irrelevant".
    relevance: Confidence.optional(),
    detections: z.array(
      z.object({
        type: z.enum(['ACTION', 'OBJECT', 'LANDMARK', 'LOCATION_CUE']),
        label: z.string(),
        confidence: Confidence,
        // Whether it was actually found. An absence the analysis looked for
        // is a real finding and often the decisive one — "the quest asked for
        // a sunrise and there is no sunrise here" is precisely what a decider
        // needs, and a detections list that could only express presence would
        // force it to be dropped or smuggled into a warning string. Defaults
        // true so an external provider that only reports what it saw stays
        // correct without changing anything.
        present: z.boolean().default(true),
        timestampsMs: z.array(z.number().int().nonnegative()),
      }),
    ),
    keyFrames: z
      .array(
        z.object({
          frameRef: z.string(),
          timestampMs: z.number().int().nonnegative(),
          reason: z.string(),
        }),
      )
      .max(12),
    integrity: z
      .object({
        manipulationLikely: z.boolean(),
        // Set when the analysis found something that must prevent an
        // AUTOMATED approval whatever the content shows — a capture time
        // outside the quest window, a byte-identical copy of someone else's
        // proof, a screenshot, a generated-content marker. Distinct from
        // manipulationLikely, which is the stronger claim that the file was
        // tampered with: a screenshot is not a forgery and still must not be
        // waved through by a machine.
        //
        // Deliberately a boolean and not a score. It is the *conclusion* of a
        // measurement, and the deciding policy needs something it can gate on
        // rather than a number it has to threshold.
        blocksAutomatedApproval: z.boolean().default(false),
        confidence: Confidence,
        notes: z.array(z.string()),
      })
      .optional(),
    warnings: z.array(z.string()),
  })
  .strict();
export type CvEvidence = z.infer<typeof CvEvidenceSchema>;

const NetworkEvidenceBase = z.object({
  provider: z.string(),
  providerReference: z.string(),
  outcome: z.enum(['SUPPORTED', 'CONTRADICTED', 'UNAVAILABLE', 'ERROR']),
  observedAt: z.string().datetime(),
  validUntil: z.string().datetime().optional(),
});

export const NetworkEvidenceSchema = z.discriminatedUnion('capability', [
  NetworkEvidenceBase.extend({
    capability: z.literal('LOCATION_VERIFICATION'),
    result: z
      .object({
        verificationResult: z.enum(['TRUE', 'PARTIAL', 'FALSE', 'UNKNOWN']).optional(),
        matchRate: z.number().min(0).max(100).optional(),
        lastLocationTime: z.string().datetime().optional(),
        matchesRequestedArea: z.boolean().optional(),
        accuracyMeters: z.number().nonnegative().optional(),
      })
      .strict(),
  }),
  NetworkEvidenceBase.extend({
    capability: z.literal('LOCATION_RETRIEVAL'),
    result: z
      .object({
        coordinates: CoordinatesSchema.optional(),
        radiusMeters: z.number().nonnegative().optional(),
        lastLocationTime: z.string().datetime().optional(),
      })
      .strict(),
  }),
  NetworkEvidenceBase.extend({
    capability: z.literal('GEOFENCING'),
    result: z
      .object({
        zoneId: z.string().optional(),
        events: z.array(
          z.object({
            type: z.enum(['ENTER', 'EXIT', 'DWELL']),
            occurredAt: z.string().datetime(),
          }),
        ),
      })
      .strict(),
  }),
  NetworkEvidenceBase.extend({
    capability: z.literal('ADDITIONAL'),
    apiName: z.string(),
    result: z.record(z.string(), z.unknown()),
  }),
]);
export type NetworkEvidence = z.infer<typeof NetworkEvidenceSchema>;
export type NetworkCapability = NetworkEvidence['capability'];

export const VerificationDecisionSchema = z
  .object({
    decision: z.enum(['APPROVED', 'REJECTED', 'HUMAN_REVIEW']),
    confidence: Confidence,
    // 1-3 reasons a user could actually read, required whenever the model
    // rejects (and useful on any decision).
    reasons: z.array(z.string().min(1)).min(1).max(3),
    evidenceAssessment: z
      .object({
        cv: z.enum(['SUPPORTS', 'CONTRADICTS', 'MISSING']),
        locationVerification: z.enum(['SUPPORTS', 'CONTRADICTS', 'MISSING']),
        locationRetrieval: z.enum(['SUPPORTS', 'CONTRADICTS', 'MISSING']),
        geofencing: z.enum(['SUPPORTS', 'CONTRADICTS', 'MISSING']),
        timing: z.enum(['SUPPORTS', 'CONTRADICTS', 'MISSING']),
      })
      .strict(),
    additionalCapabilitiesUsed: z.array(z.string()).max(5),
    conflicts: z.array(z.string()).max(5),
    humanReviewReason: z.string().optional(),
  })
  .strict()
  .superRefine((value, ctx) => {
    if (value.decision === 'HUMAN_REVIEW' && !value.humanReviewReason) {
      ctx.addIssue({ code: 'custom', path: ['humanReviewReason'], message: 'Required for HUMAN_REVIEW' });
    }
  });
export type VerificationDecision = z.infer<typeof VerificationDecisionSchema>;
