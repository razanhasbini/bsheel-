import { Module } from '@nestjs/common';
import { AgentEvidenceRepository } from './infrastructure/agent-evidence.repository.js';
import { AgentEvidenceController } from './presentation/agent-evidence.controller.js';

/**
 * The read side of agent verification, for the admin console.
 *
 * Separate from AgentModule because that one runs in the WORKER — it holds
 * the OpenAI client, the CAMARA adapters and the queues that actually
 * decide things. This is only queries over what those left behind, so it
 * belongs in the API process and carries none of that machinery.
 */
@Module({
  controllers: [AgentEvidenceController],
  providers: [AgentEvidenceRepository],
})
export class AgentEvidenceModule {}
