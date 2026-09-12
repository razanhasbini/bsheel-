import { randomUUID } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NetworkAsCodeApiClient } from 'network-as-code';
import type { Environment } from '../../config/environment.js';
import type { NetworkEvidence } from '../../modules/agent/domain/agent.schemas.js';
import { haversineMeters } from '../../modules/agent/domain/geo.js';
import type { LocationEvidenceQuery, NetworkEvidenceProvider } from '../../modules/agent/domain/network-evidence.port.js';
import { CamaraClientFactory } from './camara-client.factory.js';
import { describeCamaraError } from './camara-error.js';

/**
 * The installed `network-as-code` SDK's declared Area type only carries
 * `areaType` for a CIRCLE request/response — its own generated types don't
 * cover `center`/`radius`, which the real CAMARA Location
 * Verification/Retrieval spec requires. This is the actual wire shape,
 * used via a cast at each call site below rather than fighting the SDK's
 * incomplete types.
 */
interface CircleAreaPayload {
  readonly areaType: 'CIRCLE';
  readonly center: { readonly latitude: number; readonly longitude: number };
  readonly radius: number;
}
interface CircleAreaResult {
  readonly areaType?: string;
  readonly center?: { readonly latitude: number; readonly longitude: number };
  readonly radius?: number;
}

/**
 * Nokia Network-as-Code / CAMARA adapter for the three mandatory
 * capabilities. Location Verification and Location Retrieval are real,
 * implemented against the official SDK. Geofencing stays fail-closed — the
 * CAMARA Geofencing Subscriptions product is asynchronous (create a
 * subscription with a webhook `sink`, get events later), which needs its
 * own public callback endpoint, signature verification and subscription
 * lifecycle management. That is separate, larger work, not a same-shape
 * synchronous call like the other two. QoS on Demand / Emergency Mode
 * remains out of scope entirely.
 *
 * Every call requires a CAMARA-verified phone number
 * (LocationEvidenceQuery.phoneNumber, from users.phone_number — issue #1).
 * Without one there is no device identifier to ask CAMARA about, so the
 * call is never attempted — this is the concrete enforcement behind the
 * mandatory phone-verification gate, not just a UI nicety.
 */
@Injectable()
export class CamaraEvidenceAdapter implements NetworkEvidenceProvider {
  private readonly logger = new Logger(CamaraEvidenceAdapter.name);

  /**
   * The one optional capability the agent may reach for (#73).
   *
   * Device Reachability answers a question the mandatory three cannot: when
   * location evidence is missing, was the handset even on the network? An
   * unreachable device explains an UNAVAILABLE location result, which is
   * the difference between "we could not tell" and "they were not there" —
   * and that difference decides between HUMAN_REVIEW and a false rejection.
   *
   * It is CONTEXT and nothing more. It cannot approve or reject anything,
   * and that is structural rather than a matter of care: the policy reads
   * only MANDATORY_CAPABILITIES, so evidence filed under ADDITIONAL is
   * incapable of satisfying or failing the gate. Reachable does not mean
   * the quest was done; unreachable does not mean it was not.
   *
   * Roaming and SIM Swap are deliberately absent.
   */
  readonly supportedAdditionalCapabilities: readonly string[] = ['DEVICE_REACHABILITY'];

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly clients: CamaraClientFactory,
  ) {}

  async getBaselineEvidence(query: LocationEvidenceQuery): Promise<readonly NetworkEvidence[]> {
    return [
      await this.locationVerification(query),
      await this.locationRetrieval(query),
      await this.geofencing(query),
    ];
  }

  /**
   * Unlike the other two, this reads events the provider already pushed to
   * our webhook during the quest rather than making a live call — the
   * agent module loaded them and passed them in on the query, already
   * filtered to the quest's own window.
   */
  private async geofencing(query: LocationEvidenceQuery): Promise<NetworkEvidence> {
    const geofence = query.geofence;
    if (!geofence || geofence.status !== 'active') {
      return this.unavailable(
        query,
        'GEOFENCING',
        undefined,
        geofence?.status === 'failed'
          ? 'Geofencing subscription failed for this assignment'
          : 'No geofencing subscription covered this assignment',
      );
    }
    const entered = geofence.events.some((event) => event.type === 'ENTER');
    return {
      provider: 'nokia-network-as-code',
      providerReference: `geofencing:${query.userQuestId}`,
      capability: 'GEOFENCING',
      // A live subscription that never reported an entry is real evidence
      // the device was never inside the area while the quest was running.
      outcome: entered ? 'SUPPORTED' : 'CONTRADICTED',
      observedAt: geofence.events[0]?.occurredAt ?? new Date().toISOString(),
      result: {
        zoneId: query.place.placeId,
        events: geofence.events.map((event) => ({ type: event.type, occurredAt: event.occurredAt })),
      },
    };
  }

  async getAdditionalEvidence(query: LocationEvidenceQuery, capability: string): Promise<NetworkEvidence> {
    // The allowlist is the contract. Anything else is refused here rather
    // than attempted, so a model that invents a capability name gets
    // UNAVAILABLE instead of an unplanned provider call.
    if (capability !== 'DEVICE_REACHABILITY') {
      return this.unavailable(query, 'ADDITIONAL', capability, 'Capability is not on the allowlist');
    }
    return this.deviceReachability(query);
  }

  /**
   * Is the device on the network at all?
   *
   * The plain retrieval, not a subscription: reachability is only ever read
   * once, at decision time, to explain evidence that is already in hand.
   * Standing up subscription and webhook infrastructure to watch a device
   * continuously would be both more machinery and more surveillance than
   * the question needs.
   *
   * The outcome is always `SUPPORTED` on a successful read, which reads
   * oddly until you remember what it means: this capability supports the
   * agent's REASONING, it does not support the claim that a quest was
   * completed. Marking an unreachable device CONTRADICTED would be exactly
   * the false-rejection signal this was chosen to prevent.
   */
  private async deviceReachability(query: LocationEvidenceQuery): Promise<NetworkEvidence> {
    const client = this.clientOrNull();
    if (!client) return this.unavailable(query, 'ADDITIONAL', 'DEVICE_REACHABILITY', 'CAMARA is not configured');
    if (!query.phoneNumber) {
      return this.unavailable(query, 'ADDITIONAL', 'DEVICE_REACHABILITY', 'No CAMARA-verified phone number on file for this user');
    }

    try {
      const response = await client.deviceStatus.retrieveReachabilityStatus({
        device: { phoneNumber: query.phoneNumber },
      });
      const connectivity = (response.connectivity ?? []).filter(
        (item): item is 'DATA' | 'SMS' => item === 'DATA' || item === 'SMS',
      );
      return {
        provider: 'nokia-network-as-code',
        providerReference: `reachability:${query.submissionId}`,
        capability: 'ADDITIONAL',
        apiName: 'DEVICE_REACHABILITY',
        outcome: 'SUPPORTED',
        observedAt: response.lastStatusTime ?? new Date().toISOString(),
        // Normalized, not the raw payload. The model needs to know whether
        // the handset could carry data, not how Nokia spells its response —
        // and the device identifier is deliberately not echoed back into
        // anything the model can read.
        result: {
          reachable: response.reachable === true,
          connectivity,
          dataConnected: connectivity.includes('DATA'),
          smsOnly: connectivity.includes('SMS') && !connectivity.includes('DATA'),
          lastStatusTime: response.lastStatusTime ?? null,
        },
      };
    } catch (error) {
      // A provider failure is UNAVAILABLE, never "unreachable". Concluding
      // the device was off because Nokia was down would be inventing
      // evidence, and it is the exact mistake CONTRADICTED-vs-UNAVAILABLE
      // exists to keep apart.
      this.logger.warn(
        { err: error, submissionId: query.submissionId },
        'Device reachability lookup failed',
      );
      return this.unavailable(query, 'ADDITIONAL', 'DEVICE_REACHABILITY', 'CAMARA call failed');
    }
  }

  private async locationVerification(query: LocationEvidenceQuery): Promise<NetworkEvidence> {
    const client = this.clientOrNull();
    if (!client) return this.unavailable(query, 'LOCATION_VERIFICATION', undefined, 'CAMARA is not configured');
    if (!query.phoneNumber) return this.unavailable(query, 'LOCATION_VERIFICATION', undefined, 'No CAMARA-verified phone number on file for this user');

    try {
      const area: CircleAreaPayload = {
        areaType: 'CIRCLE',
        center: { latitude: query.place.latitude, longitude: query.place.longitude },
        radius: query.place.radiusMeters,
      };
      const response = await client.location.verify({
        device: { phoneNumber: query.phoneNumber },
        area: area as unknown as { areaType: 'CIRCLE' },
        maxAge: this.maxAgeSeconds(query),
      });
      // CAMARA answers four ways and they do not collapse into two.
      //
      // TRUE and FALSE are positive statements about where the device is.
      // UNKNOWN is the network saying it does not know. PARTIAL is the
      // interesting one: it means the reported area overlaps the requested
      // one, and `matchRate` says by how much — but Nokia's simulator
      // returns PARTIAL with NO matchRate at all, and the previous
      // `matchRate ?? 0` read that silence as 0% and rejected on it.
      //
      // Treating an unquantified PARTIAL as a contradiction is exactly the
      // failure this pipeline exists to avoid: it turns "the network was
      // vague" into "the user was not there". Absent a rate, this is
      // uncertainty, and uncertainty goes to a human.
      const result = response.verificationResult;
      const matchRate = response.matchRate;
      let outcome: NetworkEvidence['outcome'];
      if (result === 'TRUE') {
        outcome = 'SUPPORTED';
      } else if (result === 'FALSE') {
        outcome = 'CONTRADICTED';
      } else if (result === 'PARTIAL') {
        outcome = typeof matchRate !== 'number'
          ? 'UNAVAILABLE'
          : matchRate >= 80 ? 'SUPPORTED' : 'CONTRADICTED';
      } else {
        // UNKNOWN, or anything a future API version adds.
        outcome = 'UNAVAILABLE';
      }
      return {
        provider: 'nokia-network-as-code',
        providerReference: `location-verification:${query.submissionId}:${randomUUID()}`,
        capability: 'LOCATION_VERIFICATION',
        outcome,
        observedAt: response.lastLocationTime ?? new Date().toISOString(),
        result: {
          verificationResult: response.verificationResult,
          ...(response.matchRate === undefined ? {} : { matchRate: response.matchRate }),
          ...(response.lastLocationTime ? { lastLocationTime: response.lastLocationTime } : {}),
          matchesRequestedArea: outcome === 'SUPPORTED',
        },
      };
    } catch (error) {
      this.logger.warn({ providerError: describeCamaraError(error), submissionId: query.submissionId }, 'CAMARA Location Verification call failed');
      return this.unavailable(query, 'LOCATION_VERIFICATION', undefined, 'CAMARA call failed');
    }
  }

  private async locationRetrieval(query: LocationEvidenceQuery): Promise<NetworkEvidence> {
    const client = this.clientOrNull();
    if (!client) return this.unavailable(query, 'LOCATION_RETRIEVAL', undefined, 'CAMARA is not configured');
    if (!query.phoneNumber) return this.unavailable(query, 'LOCATION_RETRIEVAL', undefined, 'No CAMARA-verified phone number on file for this user');

    try {
      const response = await client.location.retrieve({
        device: { phoneNumber: query.phoneNumber },
        maxAge: this.maxAgeSeconds(query),
      });
      // Only CIRCLE is handled — quest destinations (map_places) are always
      // a point + radius; a POLYGON response has nothing to compare against.
      const area = response.area as unknown as CircleAreaResult;
      const center = area.areaType === 'CIRCLE' ? area.center : undefined;
      if (!center) {
        return {
          provider: 'nokia-network-as-code',
          providerReference: `location-retrieval:${query.submissionId}:${randomUUID()}`,
          capability: 'LOCATION_RETRIEVAL',
          outcome: 'UNAVAILABLE',
          observedAt: response.lastLocationTime,
          result: {},
        };
      }
      const distanceMeters = haversineMeters(center, query.place);
      const outcome: NetworkEvidence['outcome'] = distanceMeters <= query.place.radiusMeters ? 'SUPPORTED' : 'CONTRADICTED';
      return {
        provider: 'nokia-network-as-code',
        providerReference: `location-retrieval:${query.submissionId}:${randomUUID()}`,
        capability: 'LOCATION_RETRIEVAL',
        outcome,
        observedAt: response.lastLocationTime,
        result: {
          coordinates: {
            latitude: center.latitude,
            longitude: center.longitude,
            ...(area.radius === undefined ? {} : { accuracyMeters: area.radius }),
          },
          ...(area.radius === undefined ? {} : { radiusMeters: area.radius }),
          ...(response.lastLocationTime ? { lastLocationTime: response.lastLocationTime } : {}),
        },
      };
    } catch (error) {
      this.logger.warn({ providerError: describeCamaraError(error), submissionId: query.submissionId }, 'CAMARA Location Retrieval call failed');
      return this.unavailable(query, 'LOCATION_RETRIEVAL', undefined, 'CAMARA call failed');
    }
  }

  /**
   * Where the network currently places this device, independent of any
   * submission. Used right after a quest is assigned to measure how far
   * the user actually is from the destination — which is what makes the
   * granted timer and the eventual XP per-user rather than per-quest.
   * Null whenever the network can't say; callers treat that as "no
   * distance information", never as "distance zero".
   */
  async retrieveCurrentLocation(
    phoneNumber: string,
    maxAgeSeconds = 3600,
  ): Promise<{ latitude: number; longitude: number } | null> {
    const client = this.clientOrNull();
    if (!client) return null;
    try {
      const response = await client.location.retrieve({
        device: { phoneNumber },
        maxAge: maxAgeSeconds,
      });
      const area = response.area as unknown as CircleAreaResult;
      if (area.areaType !== 'CIRCLE' || !area.center) return null;
      return { latitude: area.center.latitude, longitude: area.center.longitude };
    } catch (error) {
      this.logger.warn({ providerError: describeCamaraError(error) }, 'CAMARA Location Retrieval (current location) failed');
      return null;
    }
  }

  /** The shared client, or null when CAMARA is switched off or unconfigured. */
  private clientOrNull(): NetworkAsCodeApiClient | null {
    if (!this.config.get('CAMARA_ENABLED', { infer: true })) return null;
    return this.clients.clientOrNull();
  }

  /** How stale the network's own location fix may be, bounded by the assignment-to-submission window. */
  private maxAgeSeconds(query: LocationEvidenceQuery): number {
    const windowSeconds = Math.max(
      60,
      Math.round((new Date(query.windowEnd).getTime() - new Date(query.windowStart).getTime()) / 1000),
    );
    return Math.min(windowSeconds, 3600);
  }

  private async unavailable(
    query: LocationEvidenceQuery,
    capability: 'LOCATION_VERIFICATION' | 'LOCATION_RETRIEVAL' | 'GEOFENCING' | 'ADDITIONAL',
    apiName?: string,
    reason?: string,
  ): Promise<NetworkEvidence> {
    this.logger.debug({ capability, apiName, reason, submissionId: query.submissionId }, 'CAMARA evidence unavailable');
    const base = {
      provider: 'nokia-network-as-code',
      providerReference: `unavailable:${randomUUID()}`,
      outcome: 'UNAVAILABLE' as const,
      observedAt: new Date().toISOString(),
      // Carried on the evidence, not only in this debug line: the console
      // shows it beside the signal, so "NETWORK COULD NOT SAY" comes with
      // the reason it could not.
      ...(reason ? { unavailableReason: reason } : {}),
    };
    switch (capability) {
      case 'LOCATION_VERIFICATION':
        return { ...base, capability, result: {} };
      case 'LOCATION_RETRIEVAL':
        return { ...base, capability, result: {} };
      case 'GEOFENCING':
        return { ...base, capability, result: { events: [] } };
      case 'ADDITIONAL':
        return { ...base, capability, apiName: apiName ?? 'unknown', result: {} };
    }
  }
}
