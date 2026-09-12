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
    /**
     * Whose subscription this is. NOKIA means the network was genuinely
     * watching, so silence is evidence of absence. DEMO_HARNESS means the
     * subscription exists only here — nothing was ever watching, and silence
     * says nothing at all.
     */
    readonly origin: 'NOKIA' | 'DEMO_HARNESS';
    readonly events: ReadonlyArray<{
      readonly type: 'ENTER' | 'EXIT';
      readonly occurredAt: string;
      /**
       * NOKIA — the network delivered it. DEMO_HARNESS — the hackathon
       * harness generated it and delivered it through the real webhook.
       *
       * Carried so a screen can say which, and say it from persisted data
       * rather than from wording somebody chose in Flutter. It is never
       * shown to the model: where an event came from does not change what
       * it means about the device, and a verdict that moved on provenance
       * would be a verdict moving on our own bookkeeping.
       */
      readonly origin: 'NOKIA' | 'DEMO_HARNESS';
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
   * inconclusive. `capability` must be one of `supportedAdditionalCapabilities`.
   *
   * QoS on Demand / Emergency Mode is not in that list and is not meant to
   * be: Emergency Mode is a decided no, not a not-yet. An SOS button is a
   * promise that help arrives, and prioritising a data bearer is not rescue
   * — keeping the promise needs a real route to emergency services and
   * somebody on the other end of it. See the section in CLAUDE.md before
   * adding it here.
   */
  getAdditionalEvidence(query: LocationEvidenceQuery, capability: string): Promise<NetworkEvidence>;

  /** The allowlist exposed to the agent's additional-evidence tool. Empty until confirmed. */
  readonly supportedAdditionalCapabilities: readonly string[];
}
