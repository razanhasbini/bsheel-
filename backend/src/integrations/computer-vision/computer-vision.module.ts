import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { CV_EVIDENCE_PROVIDER } from '../../modules/agent/domain/agent.tokens.js';
import type { CvEvidenceProvider } from '../../modules/agent/domain/cv-evidence.port.js';
import { SubmissionsModule } from '../../modules/submissions/submissions.module.js';
import { HttpCvEvidenceProvider } from './http-cv-evidence.provider.js';
import { LocalCvEvidenceProvider } from './local-cv-evidence.provider.js';
import { NullCvEvidenceProvider } from './null-cv-evidence.provider.js';

/**
 * The one place a CV provider is chosen. All three implementations sit
 * together so that "what does the agent actually see" is one file to read:
 *
 *   local — the in-process #47 vision cascade, read from the row it already
 *           wrote for this submission. The default, because it is the only
 *           option that works without another service existing.
 *   http  — an external computer-vision service at CV_SERVICE_BASE_URL. The
 *           contract a CV engineer implements to take over.
 *   none  — fail-closed. Returns UNAVAILABLE, which sends every submission to
 *           a human. Kept as an explicit off switch rather than a default.
 *
 * `local` needs the vision cascade's stored findings, hence the import of
 * SubmissionsModule — an integrations module reaching into a feature module,
 * which is the one direction this repository otherwise avoids. It is the
 * honest shape here: the adapter's whole job is translating one domain's
 * conclusions into another domain's contract, and the alternative (a copy of
 * the cascade living under integrations/) would duplicate the expensive part
 * of the feature to preserve a diagram. The dependency is one-way —
 * SubmissionsModule knows nothing about the agent or its ports — so there is
 * no cycle.
 */
/**
 * The three-way switch, pulled out of the factory so it can be asserted
 * directly. Which provider a deployment gets decides whether the agent can
 * see the submitted media at all, and that is too consequential to be an
 * untested inline arrow — for most of this feature's life the answer was
 * silently `none`, and nothing failed to say so.
 *
 * Anything unrecognised lands on `none`, which escalates rather than guesses.
 */
export function selectCvProvider(
  setting: Environment['CV_PROVIDER'],
  providers: {
    none: CvEvidenceProvider;
    http: CvEvidenceProvider;
    local: CvEvidenceProvider;
  },
): CvEvidenceProvider {
  if (setting === 'http') return providers.http;
  if (setting === 'local') return providers.local;
  return providers.none;
}

@Module({
  imports: [SubmissionsModule],
  providers: [
    NullCvEvidenceProvider,
    HttpCvEvidenceProvider,
    LocalCvEvidenceProvider,
    {
      provide: CV_EVIDENCE_PROVIDER,
      inject: [ConfigService, NullCvEvidenceProvider, HttpCvEvidenceProvider, LocalCvEvidenceProvider],
      useFactory: (
        config: ConfigService<Environment, true>,
        none: NullCvEvidenceProvider,
        http: HttpCvEvidenceProvider,
        local: LocalCvEvidenceProvider,
      ) => selectCvProvider(config.get('CV_PROVIDER', { infer: true }), { none, http, local }),
    },
  ],
  exports: [CV_EVIDENCE_PROVIDER],
})
export class ComputerVisionModule {}
