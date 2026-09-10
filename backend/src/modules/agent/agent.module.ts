import { Module } from '@nestjs/common';
import { CamaraModule } from '../../integrations/camara/camara.module.js';
import { ComputerVisionModule } from '../../integrations/computer-vision/computer-vision.module.js';
import { MediaModule } from '../media/media.module.js';
import { AgentContextService } from './application/agent-context.service.js';
import { QuestAssignmentAgentService } from './application/quest-assignment-agent.service.js';
import { QuestTimeRecommendationService } from './application/quest-time-recommendation.service.js';
import { SubmissionVerificationService } from './application/submission-verification.service.js';
import { XpRecommendationService } from './application/xp-recommendation.service.js';
import { GeofencingModule } from './geofencing.module.js';
import { AgentContextRepository } from './infrastructure/agent-context.repository.js';
import { AgentRunsRepository } from './infrastructure/agent-runs.repository.js';
import { AgentRuntimeConfigRepository } from './infrastructure/agent-runtime-config.repository.js';
import { OpenAiAgentRunner } from './infrastructure/openai/openai-agent.runner.js';

/**
 * The AI agent phase, submission-verification slice. Note this module does
 * NOT provide SubmissionVerificationProcessor — that BullMQ consumer is
 * registered directly on WorkerModule, matching how QuestMaintenanceProcessor
 * lives under modules/quests/ but is wired by worker.module.ts rather than
 * by QuestsModule. Feature modules own domain logic; WorkerModule owns the
 * queue-consuming glue.
 */
@Module({
  imports: [CamaraModule, ComputerVisionModule, MediaModule, GeofencingModule],
  providers: [
    AgentContextRepository,
    AgentContextService,
    AgentRunsRepository,
    AgentRuntimeConfigRepository,
    OpenAiAgentRunner,
    SubmissionVerificationService,
    QuestAssignmentAgentService,
    QuestTimeRecommendationService,
    XpRecommendationService,
  ],
  exports: [
    SubmissionVerificationService,
    QuestAssignmentAgentService,
    QuestTimeRecommendationService,
    XpRecommendationService,
    AgentContextService,
  ],
})
export class AgentModule {}
