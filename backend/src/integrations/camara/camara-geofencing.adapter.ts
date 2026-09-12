import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NetworkAsCodeApiClient } from 'network-as-code';
import type { Environment } from '../../config/environment.js';
import { CamaraClientFactory } from './camara-client.factory.js';
import { describeCamaraError } from './camara-error.js';

export interface GeofenceSubscriptionRequest {
  readonly phoneNumber: string;
  readonly place: {
    readonly latitude: number;
    readonly longitude: number;
    readonly radiusMeters: number;
  };
  /** Public callback URL. The secret travels as a bearer sink credential, never in the URL. */
  readonly sink: string;
  readonly sinkBearerToken: string;
  readonly expiresAt: Date;
}

export type GeofenceSubscriptionResult =
  | { readonly ok: true; readonly providerSubscriptionIds: readonly string[] }
  | { readonly ok: false; readonly reason: string };

/**
 * Creates and cancels CAMARA Geofencing Subscriptions. Separate from
 * CamaraEvidenceAdapter because the shape of the interaction is different:
 * Location Verification/Retrieval are synchronous questions, while
 * geofencing is "tell me later" — the provider posts entry/exit events to
 * our webhook for the life of the subscription.
 *
 * Nokia enforces one event type per subscription, so entry and exit use two
 * provider subscriptions pointing at the same authenticated sink. The
 * generated SDK type omits the access-token fields, but Nokia's documented
 * wire contract includes them and sends the token back as Authorization:
 * Bearer on notifications.
 */
@Injectable()
export class CamaraGeofencingAdapter {
  private readonly logger = new Logger(CamaraGeofencingAdapter.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly clients: CamaraClientFactory,
  ) {}

  isConfigured(): boolean {
    return Boolean(
      this.config.get('CAMARA_ENABLED', { infer: true }) && this.config.get('CAMARA_API_KEY', { infer: true }),
    );
  }

  async createSubscription(request: GeofenceSubscriptionRequest): Promise<GeofenceSubscriptionResult> {
    const client = this.clientOrNull();
    if (!client) return { ok: false, reason: 'CAMARA is not configured' };

    const created: string[] = [];
    try {
      for (const type of [
        'org.camaraproject.geofencing-subscriptions.v0.area-entered',
        'org.camaraproject.geofencing-subscriptions.v0.area-left',
      ] as const) {
        const response = await client.geofencing.createSubscription({
          protocol: 'HTTP',
          sink: request.sink,
          sinkCredential: {
            credentialType: 'ACCESSTOKEN',
            accessToken: request.sinkBearerToken,
            accessTokenExpiresUtc: request.expiresAt.toISOString(),
            accessTokenType: 'bearer',
          } as unknown as { credentialType: 'ACCESSTOKEN' },
          types: [type],
          config: {
            subscriptionDetail: {
              device: { phoneNumber: request.phoneNumber },
              // Same typed-surface gap as Location: the SDK declares only
              // areaType, while the CAMARA spec needs center + radius.
              area: {
                areaType: 'CIRCLE',
                center: { latitude: request.place.latitude, longitude: request.place.longitude },
                radius: request.place.radiusMeters,
              } as unknown as { areaType: 'CIRCLE' },
            },
            subscriptionExpireTime: request.expiresAt.toISOString(),
            initialEvent: type.endsWith('area-entered'),
          },
        });
        if (!response.id) throw new Error('Provider returned no subscription id');
        created.push(response.id);
      }
      return { ok: true, providerSubscriptionIds: created };
    } catch (error) {
      await Promise.all(created.map((id) => this.deleteSubscription(id)));
      const descriptor = describeCamaraError(error);
      const reason = describeSubscriptionFailure(descriptor);
      this.logger.warn({ providerError: descriptor }, 'CAMARA geofencing subscription failed');
      return { ok: false, reason };
    }
  }

  /// Best-effort cleanup once a quest is done with. A provider subscription
  /// also carries its own expiry, so a failure here is not fatal.
  async deleteSubscription(providerSubscriptionId: string): Promise<void> {
    const client = this.clientOrNull();
    if (!client) return;
    try {
      await client.geofencing.deleteSubscription({ subscriptionId: providerSubscriptionId });
    } catch (error) {
      this.logger.warn({ providerError: describeCamaraError(error), providerSubscriptionId }, 'CAMARA geofencing unsubscribe failed');
    }
  }

  private clientOrNull(): NetworkAsCodeApiClient | null {
    if (!this.isConfigured()) return null;
    return this.clients.clientOrNull();
  }
}

/**
 * Turn a provider error into something an operator can act on.
 *
 * This function exists because the previous one line — "Provider returned
 * HTTP ${status}" — cost a day. Every geofence in this deployment was failing
 * with HTTP 404, which reads as "the API is not there" and sent the
 * investigation at routing and entitlement. It was neither. Measured against
 * the live gateway on 2026-09-13, on the same key and the same client that
 * Location Verification succeeds on:
 *
 *   POST geofencing-subscriptions/v0.3/subscriptions, device +99999991001
 *     → 201 Created
 *   the same request, device +96170123456
 *     → 404 { "detail": "Target not found" }
 *
 * So the 404 is about the DEVICE, not the endpoint: Nokia will only watch a
 * device the network knows, and in a simulator-backed sandbox the only such
 * devices are the simulator MSISDNs. A real player's number cannot be watched
 * here, and no amount of configuration changes that.
 *
 * The three cases are kept apart because they have three different fixes —
 * change the device, buy the entitlement, call support — and a reason string
 * that collapses them sends whoever reads it to the wrong one.
 */
export function describeSubscriptionFailure(descriptor: {
  readonly status?: number;
  readonly detail?: string;
}): string {
  const detail = descriptor.detail ? ` — the provider said: ${descriptor.detail}` : '';
  switch (descriptor.status) {
    case 404:
      return 'The network does not know this device, so there is nothing to watch. '
        + 'Geofencing can only be opened for a device provisioned on the operator; '
        + 'on a simulator-backed deployment that means one of Nokia\'s simulator '
        + `MSISDNs${detail}`;
    case 403:
      return `This deployment is not entitled to CAMARA Geofencing Subscriptions${detail}`;
    case 401:
      return `The CAMARA credentials were rejected${detail}`;
    default:
      return descriptor.status
        ? `Geofencing subscription failed: provider returned HTTP ${descriptor.status}${detail}`
        : 'Geofencing subscription failed before the provider answered';
  }
}
