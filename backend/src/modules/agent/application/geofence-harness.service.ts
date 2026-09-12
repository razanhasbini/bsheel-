import { randomUUID } from 'node:crypto';
import { ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { GeofencingRepository } from '../infrastructure/geofencing.repository.js';

/**
 * CAMARA geofencing CloudEvent types, exactly as our own subscription
 * registers them with Nokia (`camara-geofencing.adapter.ts`) and exactly as
 * `geofencing-callback.spec.ts` pins the parser against.
 *
 * Declared here once so the harness cannot invent a shape the parser merely
 * happens to accept — the whole value of the harness is that it exercises
 * the real contract.
 */
export const GEOFENCE_CLOUDEVENT_TYPES = {
  AREA_ENTERED: 'org.camaraproject.geofencing-subscriptions.v0.area-entered',
  AREA_LEFT: 'org.camaraproject.geofencing-subscriptions.v0.area-left',
} as const;

export type GeofenceHarnessEvent = keyof typeof GEOFENCE_CLOUDEVENT_TYPES;

export interface GeofenceDelivery {
  readonly subscriptionId: string;
  readonly eventId: string;
  readonly type: GeofenceHarnessEvent;
  readonly occurredAt: string;
  readonly httpStatus: number;
  readonly created: boolean;
}

/**
 * Delivers a Nokia-shaped geofence CloudEvent to our own webhook, over HTTP.
 *
 * **Why this exists.** CAMARA geofencing is subscription-based: we register a
 * sink and the network pushes entry/exit events to it later. Nothing can push
 * to a laptop, so on a developer machine — and on a staging box the simulator
 * never calls back to — the mandatory geofence signal is permanently
 * UNAVAILABLE. The policy then refuses to approve anything, which is correct
 * and also means the supportive half of the demo can never be shown.
 *
 * **What makes it honest.** It delivers over real HTTP to the real route,
 * authenticated by the real per-subscription bearer secret, parsed by the real
 * parser, persisted by the real repository, and picked up by the real
 * late-evidence recovery. Nothing here writes a geofence row directly, and the
 * callback endpoint gains no test-only branch — if the secret is wrong the
 * harness gets the same flat 404 a stranger would.
 *
 * **What it is not.** Evidence that a carrier observed anything. The
 * subscription it creates exists nowhere but our database, so Nokia could not
 * deliver to it even in principle; every event on it is stamped
 * `DEMO_HARNESS` and must be shown that way.
 */
@Injectable()
export class GeofenceHarnessService {
  private readonly logger = new Logger(GeofenceHarnessService.name);

  constructor(
    private readonly geofencing: GeofencingRepository,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  /**
   * Refused on production, and not only by configuration.
   *
   * The harness fabricates evidence-shaped data. It is fenced by the same
   * switch as the simulator personas — which production refuses at boot — but
   * this second check means a future caller cannot reach it by forgetting the
   * first.
   */
  private assertPermitted(): void {
    const nodeEnv = this.config.get('NODE_ENV', { infer: true });
    if (nodeEnv === 'production') {
      throw new ForbiddenException({
        code: 'HARNESS_FORBIDDEN',
        message: 'The geofence harness cannot run on production',
      });
    }
    if (!this.config.get('CAMARA_DEMO_PERSONAS_ENABLED', { infer: true })) {
      throw new ForbiddenException({
        code: 'HARNESS_DISABLED',
        message: 'Demo tooling is not enabled on this deployment',
      });
    }
  }

  /**
   * Ensures there is a subscription to deliver to, and says whether it had to
   * make one.
   *
   * A real destination quest already has a subscription — the assignment agent
   * opens it — and the harness reuses it, keeping its NOKIA provenance because
   * that is the truth about the subscription even if this particular event is
   * ours. Where none exists (no CAMARA credentials, or the adapter failed) it
   * creates one marked DEMO_HARNESS.
   */
  private async subscriptionFor(userQuest: {
    id: string;
    placeId: string;
    startsAt: Date;
    expiresAt: Date;
  }) {
    const existing = await this.geofencing.findByUserQuest(userQuest.id);
    if (existing) {
      // Take it over unless it is already ours and already collecting. A
      // failed Nokia registration is the usual case — nothing can call back
      // to a laptop — and a subscription left 'failed' makes the geofence
      // signal permanently unavailable however many events we deliver to it.
      // Adopting also re-stamps the origin, so the events cannot be read as
      // carrier observations.
      if (existing.status !== 'active' || existing.origin !== 'DEMO_HARNESS') {
        await this.geofencing.adoptForHarness(existing.id);
        return {
          subscription: { ...existing, status: 'active' as const, origin: 'DEMO_HARNESS' as const },
          created: false,
        };
      }
      return { subscription: existing, created: false };
    }

    const created = await this.geofencing.create({
      userQuestId: userQuest.id,
      placeId: userQuest.placeId,
      // Never logged, never returned. It authenticates the delivery below and
      // nothing else needs it.
      callbackSecret: randomUUID(),
      startsAt: userQuest.startsAt,
      expiresAt: userQuest.expiresAt,
      origin: 'DEMO_HARNESS',
    });
    if (created) {
      // `loadGeofence` ignores a subscription that is not active, so a
      // pending one would collect events nobody reads — the harness would
      // look broken while behaving correctly. There is no provider
      // subscription behind it, and the empty list says so.
      await this.geofencing.markActive(created.id, []);
      return { subscription: { ...created, status: 'active' as const }, created: true };
    }
    if (!created) {
      // Lost the race with something else creating it; re-read.
      const raced = await this.geofencing.findByUserQuest(userQuest.id);
      if (!raced) {
        throw new NotFoundException({
          code: 'NO_GEOFENCE_SUBSCRIPTION',
          message: 'Could not open a geofence subscription for that quest',
        });
      }
      return { subscription: raced, created: false };
    }
    return { subscription: created, created: true };
  }

  /**
   * Forgets whatever this harness previously fabricated for a quest.
   *
   * Called before each demo scenario so the one that follows is a clean
   * question rather than the last one's leftovers. Nokia-delivered events
   * survive untouched — the harness only ever unmakes its own work.
   */
  async clearPreviousEvents(userQuestId: string): Promise<number> {
    this.assertPermitted();
    return this.geofencing.clearHarnessEvents(userQuestId);
  }

  /**
   * Builds the CloudEvent and POSTs it to our own callback.
   *
   * `occurredAt` defaults to now, clamped into the subscription's window —
   * an event outside the quest window is correctly ignored when the evidence
   * is read back, so a harness that let you place one there would look broken
   * rather than strict.
   */
  async deliver(input: {
    userQuest: {
      id: string;
      placeId: string;
      startsAt: Date;
      expiresAt: Date;
      /** When the proof was submitted; the end of the window evidence is read in. */
      submittedAt?: Date | null;
    };
    type: GeofenceHarnessEvent;
    occurredAt?: Date;
  }): Promise<GeofenceDelivery> {
    this.assertPermitted();
    const { subscription, created } = await this.subscriptionFor(input.userQuest);

    // Clamped into the window the evidence is actually READ in — assignment
    // through submission — not merely into the subscription's lifetime. An
    // event stamped "now" on an already-submitted quest lands after that
    // window and is correctly ignored, which reads as the harness being
    // broken when it is the policy being strict. Defaulting to a moment just
    // inside the window is the honest placement: the harness is asserting
    // "the device crossed the boundary while the quest was running".
    const ceilingMs = Math.min(
      subscription.expiresAt.getTime(),
      input.userQuest.submittedAt?.getTime() ?? Date.now(),
    );
    const floorMs = subscription.startsAt.getTime();
    const requested = input.occurredAt?.getTime() ?? ceilingMs;
    const occurredAt = new Date(Math.min(Math.max(requested, floorMs), ceilingMs));

    const eventId = `demo-harness-${randomUUID()}`;
    const body = {
      // The CloudEvents envelope Nokia sends, as pinned by
      // geofencing-callback.spec.ts and registered by our own subscription.
      id: eventId,
      type: GEOFENCE_CLOUDEVENT_TYPES[input.type],
      source: 'bsheel://demo-cloudevent-harness',
      specversion: '1.0',
      time: occurredAt.toISOString(),
      data: { subscriptionId: subscription.id },
    };

    const url = `${this.callbackBaseUrl()}/api/v1/integrations/camara/geofencing/${subscription.id}`;
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        // The real per-subscription credential. A wrong one gets the same
        // flat 404 anybody else would, which is the point of going through
        // the wire rather than calling the repository.
        authorization: `Bearer ${subscription.callbackSecret}`,
      },
      body: JSON.stringify(body),
    });

    this.logger.log(
      {
        subscriptionId: subscription.id,
        type: input.type,
        status: response.status,
        origin: subscription.origin,
        createdSubscription: created,
      },
      'Delivered a demo geofence CloudEvent through the real webhook',
    );

    return {
      subscriptionId: subscription.id,
      eventId,
      type: input.type,
      occurredAt: occurredAt.toISOString(),
      httpStatus: response.status,
      created,
    };
  }

  /** Where our own API answers. Not the public CAMARA sink, which a laptop has no way to be. */
  private callbackBaseUrl(): string {
    const configured = this.config.get('DEMO_HARNESS_CALLBACK_BASE_URL', { infer: true });
    if (configured) return configured.replace(/\/$/, '');
    return `http://127.0.0.1:${this.config.get('PORT', { infer: true })}`;
  }
}
