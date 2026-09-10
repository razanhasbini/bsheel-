import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { QuestAssignmentAgentService } from '../application/quest-assignment-agent.service.js';

interface QuestAssignmentPayload {
  readonly userQuestId: string;
}

const CONCURRENCY = Number(process.env.QUEST_ASSIGNMENT_AGENT_CONCURRENCY) || 2;

/**
 * Runs the post-assignment work — distance measurement, personalised
 * timer, geofence — off the HTTP path and out of the shared domain-events
 * processor, because it makes CAMARA and OpenAI calls.
 */
@Injectable()
@Processor('quest-assignment-agent', { concurrency: CONCURRENCY })
export class QuestAssignmentAgentProcessor extends WorkerHost {
  private readonly logger = new Logger(QuestAssignmentAgentProcessor.name);

  constructor(private readonly service: QuestAssignmentAgentService) {
    super();
  }

  async process(job: Job<Record<string, unknown>, unknown, string>): Promise<void> {
    if (job.name !== 'quest.assignment-agent') {
      throw new Error(`Unknown quest-assignment-agent job: ${job.name}`);
    }
    const payload = this.payload(job.data);
    await this.service.process(payload.userQuestId);
    this.logger.debug({ userQuestId: payload.userQuestId }, 'Quest assignment post-processing finished');
  }

  private payload(data: Record<string, unknown>): QuestAssignmentPayload {
    if (typeof data.userQuestId !== 'string') {
      throw new Error('quest.assignment-agent payload is malformed');
    }
    return { userQuestId: data.userQuestId };
  }
}
