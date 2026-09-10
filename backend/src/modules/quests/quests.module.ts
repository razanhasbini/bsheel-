import { Module } from '@nestjs/common';
import { QuestsService } from './application/quests.service.js';
import { QuestsRepository } from './infrastructure/quests.repository.js';
import { QuestsController } from './presentation/quests.controller.js';
import { QuestAssignmentPolicyRepository } from './infrastructure/quest-assignment-policy.repository.js';
import { QuestMaintenanceService } from './application/quest-maintenance.service.js';

@Module({
  controllers: [QuestsController],
  providers: [QuestsService, QuestsRepository, QuestAssignmentPolicyRepository, QuestMaintenanceService],
  exports: [QuestsService, QuestAssignmentPolicyRepository, QuestMaintenanceService],
})
export class QuestsModule {}
