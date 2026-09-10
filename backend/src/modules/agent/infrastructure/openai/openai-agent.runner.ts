import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { run, setDefaultOpenAIClient, setTracingDisabled, setTracingExportApiKey } from '@openai/agents';
import type { Agent } from '@openai/agents';
import OpenAI from 'openai';
import type { Environment } from '../../../../config/environment.js';

/**
 * Thin wrapper around the official OpenAI Agents SDK. Owns exactly two
 * things: constructing the OpenAI client once from server-side config, and
 * running an already-built Agent. It never sees CAMARA credentials, never
 * touches the database, and never decides anything — it returns whatever
 * the model produced for the caller (submission-verification.service.ts,
 * etc.) to validate and clamp.
 */
@Injectable()
export class OpenAiAgentRunner {
  private readonly logger = new Logger(OpenAiAgentRunner.name);
  private initialized = false;

  constructor(private readonly config: ConfigService<Environment, true>) {}

  isEnabled(): boolean {
    return this.config.get('OPENAI_AGENT_ENABLED', { infer: true });
  }

  async run<TOutput>(agent: Agent<unknown, any>, input: string): Promise<TOutput> {
    if (!this.isEnabled()) {
      throw new Error('OpenAiAgentRunner.run called while OPENAI_AGENT_ENABLED=false');
    }
    this.ensureInitialized();
    const result = await run(agent, input, {
      maxTurns: this.config.get('OPENAI_AGENT_MAX_TURNS', { infer: true }),
    });
    return result.finalOutput as TOutput;
  }

  private ensureInitialized(): void {
    if (this.initialized) return;
    const apiKey = this.config.get('OPENAI_API_KEY', { infer: true });
    if (!apiKey) {
      // environment.ts already requires this when OPENAI_AGENT_ENABLED is
      // true; this is a defensive second guard, not the primary one.
      throw new Error('OPENAI_API_KEY is required when OPENAI_AGENT_ENABLED is true');
    }
    const client = new OpenAI({
      apiKey,
      project: this.config.get('OPENAI_PROJECT_ID', { infer: true }),
      organization: this.config.get('OPENAI_ORGANIZATION_ID', { infer: true }),
      timeout: this.config.get('OPENAI_AGENT_TIMEOUT_MS', { infer: true }),
    });
    setDefaultOpenAIClient(client);
    const tracingEnabled = this.config.get('OPENAI_TRACING_ENABLED', { infer: true });
    setTracingDisabled(!tracingEnabled);
    if (tracingEnabled) {
      setTracingExportApiKey(apiKey);
    }
    this.logger.log('OpenAI agent runtime initialized');
    this.initialized = true;
  }
}
