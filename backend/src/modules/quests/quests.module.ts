import { Module } from '@nestjs/common';
import { QuestCampaignsService } from './application/quest-campaigns.service.js';
import { QuestsService } from './application/quests.service.js';
import { QuestCampaignsRepository } from './infrastructure/quest-campaigns.repository.js';
import { QuestsRepository } from './infrastructure/quests.repository.js';
import { QuestCampaignsController } from './presentation/quest-campaigns.controller.js';
import { QuestsController } from './presentation/quests.controller.js';
import { QuestAuthoringController } from './presentation/quest-authoring.controller.js';
import { QuestAuthoringRepository } from './infrastructure/quest-authoring.repository.js';
import { JourneyRepository } from './infrastructure/journey.repository.js';
import { JourneyProgressionService } from './application/journey-progression.service.js';
import { JourneyNotifier } from './application/journey-notifier.service.js';
import { QuestAssignmentPolicyRepository } from './infrastructure/quest-assignment-policy.repository.js';
import { QuestMaintenanceService } from './application/quest-maintenance.service.js';

@Module({
  controllers: [QuestsController, QuestCampaignsController, QuestAuthoringController],
  providers: [
    QuestsService,
    QuestsRepository,
    QuestAssignmentPolicyRepository,
    QuestMaintenanceService,
    QuestCampaignsService,
    QuestCampaignsRepository,
    QuestAuthoringRepository,
    JourneyRepository,
    JourneyProgressionService,
    JourneyNotifier,
  ],
  exports: [
    QuestsService, QuestAssignmentPolicyRepository, QuestMaintenanceService,
    // The outbox processor advances journeys off submission.approved.
    JourneyProgressionService, JourneyNotifier, JourneyRepository,
  ],
})
export class QuestsModule {}
