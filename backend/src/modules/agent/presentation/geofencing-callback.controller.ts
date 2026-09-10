import { Body, Controller, Headers, HttpCode, Logger, NotFoundException, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../../../common/auth/public.decorator.js';
import { GeofencingRepository } from '../infrastructure/geofencing.repository.js';
import { GeofencingCallbackParams } from './geofencing-callback.dto.js';

/**
 * Where CAMARA delivers geofence entry/exit events for a running quest.
 *
 * Public by necessity — the provider has no Bsheel session. Authentication
 * is the per-subscription bearer sink credential, compared against
 * geofencing_subscriptions.callback_secret: a caller who doesn't already
 * know both the subscription id and its secret cannot record an event.
 * Unknown or mismatched pairs get a flat 404 so this cannot be used to
 * probe which subscription ids exist.
 *
 * Events are only ever *read back* inside the quest's own window (see
 * GeofencingRepository.eventsInWindow), so a late or replayed delivery
 * cannot manufacture presence during a quest that already ended.
 */
@ApiTags('integrations')
@Controller({ path: 'integrations/camara/geofencing', version: '1' })
export class GeofencingCallbackController {
  private readonly logger = new Logger(GeofencingCallbackController.name);

  constructor(private readonly geofencing: GeofencingRepository) {}

  @Public()
  @Throttle({ default: { limit: 120, ttl: 60_000 } })
  @HttpCode(204)
  @Post(':subscriptionId')
  @ApiOperation({ summary: 'CAMARA geofencing event sink (provider callback)' })
  async receive(
    @Param() params: GeofencingCallbackParams,
    @Headers('authorization') authorization: string | undefined,
    @Body() body: Record<string, unknown>,
  ): Promise<void> {
    const subscription = await this.geofencing.findById(params.subscriptionId);
    if (!subscription || authorization !== `Bearer ${subscription.callbackSecret}`) {
      throw new NotFoundException({ code: 'NOT_FOUND', message: 'Not found' });
    }

    const event = this.parseEvent(body);
    if (!event) {
      this.logger.warn({ subscriptionId: params.subscriptionId }, 'Unrecognised geofencing callback payload');
      return;
    }

    await this.geofencing.recordEvent({
      subscriptionId: subscription.id,
      type: event.type,
      occurredAt: event.occurredAt,
      providerEventId: event.providerEventId,
    });
  }

  /**
   * CAMARA delivers CloudEvents: a `type` of
   * org.camaraproject.geofencing-subscriptions.v0.area-entered / area-left,
   * an `id`, and a `time`. Anything we can't recognise is dropped rather
   * than guessed at — an unparsed callback must never become evidence.
   */
  private parseEvent(
    body: Record<string, unknown>,
  ): { type: 'ENTER' | 'EXIT'; occurredAt: Date; providerEventId?: string } | null {
    const rawType = typeof body.type === 'string' ? body.type : '';
    const type = rawType.endsWith('area-entered')
      ? 'ENTER'
      : rawType.endsWith('area-left')
        ? 'EXIT'
        : null;
    if (!type) return null;

    const rawTime = typeof body.time === 'string' ? body.time : undefined;
    const occurredAt = rawTime ? new Date(rawTime) : new Date();
    if (Number.isNaN(occurredAt.getTime())) return null;

    return {
      type,
      occurredAt,
      providerEventId: typeof body.id === 'string' ? body.id : undefined,
    };
  }
}
