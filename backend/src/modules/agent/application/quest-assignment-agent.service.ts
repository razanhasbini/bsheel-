import { randomBytes } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { CamaraEvidenceAdapter } from '../../../integrations/camara/camara-evidence.adapter.js';
import { CamaraGeofencingAdapter } from '../../../integrations/camara/camara-geofencing.adapter.js';
import { haversineMeters } from '../domain/geo.js';
import {
  deterministicQuestMinutes,
  resolvePolicyBounds,
  type RewardShapeInputs,
} from '../domain/verification-policy.js';
import { AgentContextRepository, type AssignmentContextRow } from '../infrastructure/agent-context.repository.js';
import { GeofencingRepository } from '../infrastructure/geofencing.repository.js';
import { AgentContextService } from './agent-context.service.js';
import { QuestTimeRecommendationService } from './quest-time-recommendation.service.js';

/**
 * Everything that happens just after a quest is assigned, off the HTTP
 * path (driven by the quest.assigned outbox event, so accepting a quest
 * never waits on a network round trip):
 *
 *  1. Ask CAMARA where the user actually is and measure the distance to
 *     the destination. This is what makes the same quest worth a different
 *     amount of time and XP to two different users.
 *  2. Grant a timer shaped by that distance, the category and the
 *     difficulty, clamped to the 4-hour / 2-week policy bounds.
 *  3. Open a geofence around the destination for exactly that window, so
 *     "did they actually go there?" is answered by entry events that can
 *     only have happened DURING the quest.
 */
@Injectable()
export class QuestAssignmentAgentService {
  private readonly logger = new Logger(QuestAssignmentAgentService.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly contextService: AgentContextService,
    private readonly contextRepository: AgentContextRepository,
    private readonly questTime: QuestTimeRecommendationService,
    private readonly camara: CamaraEvidenceAdapter,
    private readonly geofencingProvider: CamaraGeofencingAdapter,
    private readonly geofencing: GeofencingRepository,
  ) {}

  async process(userQuestId: string): Promise<void> {
    if (!this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) return;

    const assignment = await this.contextRepository.findAssignmentContext(userQuestId);
    if (!assignment) {
      // Already submitted, expired or rerolled between the event being
      // emitted and this running. Nothing to adjust.
      return;
    }

    const distanceMeters = await this.measureDistance(assignment);
    if (distanceMeters !== null) {
      await this.contextRepository.storeAssignmentDistance(userQuestId, distanceMeters);
    }

    const expiresAt = await this.applyTimer(assignment, distanceMeters);
    await this.openGeofence(assignment, expiresAt);
  }

  /// Network-measured distance from the user to the destination. Null for
  /// a quest with no destination (nothing to travel to) or when CAMARA
  /// cannot place the device — never guessed from a client coordinate.
  private async measureDistance(assignment: AssignmentContextRow): Promise<number | null> {
    if (assignment.latitude === null || assignment.longitude === null) return null;
    if (!assignment.phone_number) return null;

    const current = await this.camara.retrieveCurrentLocation(assignment.phone_number);
    if (!current) return null;
    return haversineMeters(current, {
      latitude: assignment.latitude,
      longitude: assignment.longitude,
    });
  }

  private async applyTimer(assignment: AssignmentContextRow, distanceMeters: number | null): Promise<Date> {
    const bounds = resolvePolicyBounds(
      { baseXp: assignment.base_xp, defaultDurationHours: assignment.default_duration_hours },
      this.contextService.policyLimits(),
    );
    const shape: RewardShapeInputs = {
      distanceMeters,
      hasDestination: assignment.place_id !== null,
      category: assignment.category,
      difficulty: assignment.difficulty,
      participantCount: 1,
    };
    const deterministicMinutes = deterministicQuestMinutes(shape, bounds);
    const recommendation = await this.questTime.recommendForAssignment({
      assignment,
      distanceMeters,
      bounds,
      deterministicMinutes,
    });

    const expiresAt = new Date(assignment.assigned_at.getTime() + recommendation.recommendedMinutes * 60_000);
    const applied = await this.contextRepository.applyRecommendedExpiry(assignment.user_quest_id, expiresAt);
    this.logger.log(
      {
        userQuestId: assignment.user_quest_id,
        distanceMeters,
        deterministicMinutes,
        grantedMinutes: recommendation.recommendedMinutes,
        applied,
      },
      'Quest timer personalised for this user',
    );
    return applied ? expiresAt : assignment.expires_at;
  }

  private async openGeofence(assignment: AssignmentContextRow, expiresAt: Date): Promise<void> {
    if (
      assignment.place_id === null ||
      assignment.latitude === null ||
      assignment.longitude === null ||
      !assignment.phone_number ||
      !this.geofencingProvider.isConfigured()
    ) {
      return;
    }

    const callbackSecret = randomBytes(24).toString('base64url');
    const subscription = await this.geofencing.create({
      userQuestId: assignment.user_quest_id,
      placeId: assignment.place_id,
      callbackSecret,
      startsAt: assignment.assigned_at,
      expiresAt,
    });
    // Null means a concurrent run already claimed this assignment's single
    // subscription slot — never create a second provider subscription.
    if (!subscription) return;

    const sinkBase = this.config.get('CAMARA_GEOFENCING_SINK_BASE_URL', { infer: true });
    if (!sinkBase) {
      await this.geofencing.markFailed(subscription.id, 'CAMARA_GEOFENCING_SINK_BASE_URL is not configured');
      return;
    }

    const result = await this.geofencingProvider.createSubscription({
      phoneNumber: assignment.phone_number,
      place: {
        latitude: assignment.latitude,
        longitude: assignment.longitude,
        radiusMeters: assignment.radius_m ?? 250,
      },
      sink: `${sinkBase.replace(/\/$/, '')}/${subscription.id}`,
      sinkBearerToken: callbackSecret,
      expiresAt,
    });

    if (result.ok) {
      await this.geofencing.markActive(subscription.id, result.providerSubscriptionIds);
      this.logger.log({ userQuestId: assignment.user_quest_id }, 'Geofence opened for the quest window');
    } else {
      await this.geofencing.markFailed(subscription.id, result.reason);
      this.logger.warn(
        { userQuestId: assignment.user_quest_id, reason: result.reason },
        'Geofence could not be opened; location-based approval will need a human',
      );
    }
  }
}
