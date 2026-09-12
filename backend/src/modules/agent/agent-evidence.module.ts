import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { AgentEvidenceRepository } from './infrastructure/agent-evidence.repository.js';
import { AgentEvidenceController } from './presentation/agent-evidence.controller.js';
import { DemoEvaluationService } from './application/demo-evaluation.service.js';
import { GeofenceHarnessService } from './application/geofence-harness.service.js';
import { GeofencingRepository } from './infrastructure/geofencing.repository.js';
import { DemoEvaluationController } from './presentation/demo-evaluation.controller.js';

/**
 * The read side of agent verification, for the admin console.
 *
 * Separate from AgentModule because that one runs in the WORKER — it holds
 * the OpenAI client, the CAMARA adapters and the queues that actually
 * decide things. This is only queries over what those left behind, so it
 * belongs in the API process and carries none of that machinery.
 */
@Module({
  // The demo lives here rather than in AgentModule for the same reason the
  // evidence reader does: it runs in the API process. It queues work for the
  // worker and reads what the worker left behind; it holds no OpenAI client
  // and no CAMARA credentials.
  imports: [BullModule.registerQueue({ name: 'submission-verification' })],
  controllers: [AgentEvidenceController, DemoEvaluationController],
  providers: [AgentEvidenceRepository, DemoEvaluationService, GeofenceHarnessService, GeofencingRepository],
})
export class AgentEvidenceModule {}
