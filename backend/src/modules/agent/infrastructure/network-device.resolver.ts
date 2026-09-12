import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { personaById } from '../../../integrations/camara/camara-personas.js';
import type { NetworkDeviceResolver, ResolvedNetworkDevice } from '../domain/network-device.port.js';
import { AgentContextService } from '../application/agent-context.service.js';

/**
 * The one place a CAMARA device identifier is decided.
 *
 * Two rules, and the second is the safety:
 *
 * **Without a persona, this is the live path and nothing else.** The
 * identifier is `users.phone_number` — the number a completed Number
 * Verification wrote. If there is none, the answer is null with a reason,
 * and every adapter turns that into UNAVAILABLE. There is deliberately no
 * fallback: a live run that cannot identify the device must not quietly
 * become a run about some other device. That is the failure mode §21 of the
 * demo spec forbids, and it is forbidden here rather than in the caller,
 * because a caller can be added later and a resolver cannot be bypassed.
 *
 * **With a persona, the deployment must be entitled to it.** Personas are
 * refused unless `CAMARA_DEMO_PERSONAS_ENABLED` is set, which the
 * environment schema refuses to accept on production at all. An unknown
 * persona id is refused rather than ignored — silently falling back to the
 * live number would produce a run labelled as a demo that asked about a real
 * person's handset.
 */
@Injectable()
export class ConfigurableNetworkDeviceResolver implements NetworkDeviceResolver {
  private readonly logger = new Logger(ConfigurableNetworkDeviceResolver.name);

  constructor(
    private readonly contextService: AgentContextService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async resolve(input: { userId: string; personaId?: string | null }): Promise<ResolvedNetworkDevice> {
    const personaId = input.personaId?.trim();
    if (personaId) {
      if (!this.config.get('CAMARA_DEMO_PERSONAS_ENABLED', { infer: true })) {
        throw new ForbiddenException({
          code: 'DEMO_PERSONAS_DISABLED',
          message: 'Simulator personas are not enabled on this deployment',
        });
      }
      const persona = personaById(personaId);
      if (!persona) {
        throw new ForbiddenException({
          code: 'UNKNOWN_CAMARA_PERSONA',
          message: 'That is not a known Nokia simulator persona',
        });
      }
      this.logger.log(
        { userId: input.userId, persona: persona.id },
        'Resolving CAMARA device to a Nokia simulator persona for this run',
      );
      return { identifier: persona.phoneNumber, source: 'NOKIA_SIMULATOR', persona };
    }

    const phoneNumber = await this.contextService.phoneNumberForUser(input.userId);
    if (!phoneNumber) {
      return {
        identifier: null,
        source: 'LIVE_OPERATOR',
        unavailableReason: 'No CAMARA-verified phone number on file for this user',
      };
    }
    return { identifier: phoneNumber, source: 'LIVE_OPERATOR' };
  }
}
