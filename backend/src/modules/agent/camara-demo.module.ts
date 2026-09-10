import { Module } from '@nestjs/common';
import { CamaraModule } from '../../integrations/camara/camara.module.js';
import { AgentContextRepository } from './infrastructure/agent-context.repository.js';
import { AgentRunsRepository } from './infrastructure/agent-runs.repository.js';
import { GeofencingRepository } from './infrastructure/geofencing.repository.js';
import { CamaraDemoService } from './application/camara-demo.service.js';
import { CamaraDemoController } from './presentation/camara-demo.controller.js';

/**
 * The demo surface, kept in the API process because a person taps a button
 * and waits for the answer — unlike the verification pipeline, which is
 * queued work that belongs in the worker.
 *
 * It pulls in CamaraModule for the location adapters but not AgentModule,
 * so the OpenAI runner and the queue processors stay out of the API. The
 * repositories it needs are read-only here.
 */
@Module({
  imports: [CamaraModule],
  controllers: [CamaraDemoController],
  providers: [
    CamaraDemoService,
    AgentContextRepository,
    AgentRunsRepository,
    GeofencingRepository,
  ],
})
export class CamaraDemoModule {}
