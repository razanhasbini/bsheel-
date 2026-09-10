import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { CV_EVIDENCE_PROVIDER } from '../../modules/agent/domain/agent.tokens.js';
import { HttpCvEvidenceProvider } from './http-cv-evidence.provider.js';
import { NullCvEvidenceProvider } from './null-cv-evidence.provider.js';

@Module({
  providers: [
    NullCvEvidenceProvider,
    HttpCvEvidenceProvider,
    {
      provide: CV_EVIDENCE_PROVIDER,
      inject: [ConfigService, NullCvEvidenceProvider, HttpCvEvidenceProvider],
      useFactory: (config: ConfigService<Environment, true>, none: NullCvEvidenceProvider, http: HttpCvEvidenceProvider) =>
        config.get('CV_PROVIDER', { infer: true }) === 'http' ? http : none,
    },
  ],
  exports: [CV_EVIDENCE_PROVIDER],
})
export class ComputerVisionModule {}
