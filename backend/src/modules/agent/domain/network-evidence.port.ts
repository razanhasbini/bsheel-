import type { NetworkEvidence } from './agent.schemas.js';

export type MandatoryCapability = 'LOCATION_VERIFICATION' | 'LOCATION_RETRIEVAL' | 'GEOFENCING';

export const MANDATORY_CAPABILITIES: readonly MandatoryCapability[] = [
  'LOCATION_VERIFICATION',
  'LOCATION_RETRIEVAL',
  'GEOFENCING',
];

export interface LocationEvidenceQuery {
  readonly runId: string;
  readonly userId: string;
  /**
   * E.164, from users.phone_number — the CAMARA-verified device identifier
   * (issue #1 / migration 0027). Null when the submitting user has none on
   * file; every implementation must treat that as UNAVAILABLE, never as
   * license to skip the identifier and guess.
   */
  readonly phoneNumber: string | null;
  readonly userQuestId: string;
  readonly submissionId: string;
  readonly place: {
    readonly placeId: string;
    readonly latitude: number;
    readonly longitude: number;
    readonly radiusMeters: number;
  };
  /** The window the evidence must fall within — quest assignment to submission. */
  readonly windowStart: string;
  readonly windowEnd: string;
  /**
   * Geofencing is subscription-based, not a live request: the provider
   * pushed entry/exit events to our webhook while the quest was running,
   * and the agent module loads them from its own tables. They arrive here
   * already filtered to the quest's window so the provider adapter stays
   * free of database access.
   *
   * `status` distinguishes "the subscription was live and the device never
   * entered" (real evidence of absence) from "we never had a working
   * subscription" (no signal at all).
   */
  readonly geofence: {
    readonly status: 'active' | 'missing' | 'failed';
    readonly events: ReadonlyArray<{
      readonly type: 'ENTER' | 'EXIT';
      readonly occurredAt: string;
    }>;
  } | null;
}

/**
 * The CAMARA/Nokia Network-as-Code boundary. Bound in src/integrations/camara.
 * Credentials and raw provider access live only behind this interface's
 * implementation — the agent, its tools and the rest of this module only
 * ever see normalized NetworkEvidence.
 */
export interface NetworkEvidenceProvider {
  /**
   * The mandatory baseline for every location-based quest submission:
   * Location Verification, Location Retrieval and Geofencing. Always
   * fetched by the backend before the model runs — never gated behind an
   * agent tool call, because it is not optional.
   */
  getBaselineEvidence(query: LocationEvidenceQuery): Promise<readonly NetworkEvidence[]>;

  /**
   * One further CAMARA capability the agent asks for after the baseline is
   * inconclusive. `capability` must be one of `supportedAdditionalCapabilities`;
   * QoS/Emergency Mode is deliberately never in that list yet.
   */
  getAdditionalEvidence(query: LocationEvidenceQuery, capability: string): Promise<NetworkEvidence>;

  /** The allowlist exposed to the agent's additional-evidence tool. Empty until confirmed. */
  readonly supportedAdditionalCapabilities: readonly string[];
}
