import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { MediaModule } from '../media/media.module.js';
import { ProofProvenanceService } from './application/proof-provenance.service.js';
import { ProofVerificationService } from './application/proof-verification.service.js';
import { SubmissionsService } from './application/submissions.service.js';
import { ClaudeProofAnalyzer } from './infrastructure/claude-proof-analyzer.js';
import { MediaForensicsService } from './infrastructure/media-forensics.service.js';
import { OpenAiProofAnalyzer } from './infrastructure/openai-proof-analyzer.js';
import { PROOF_ANALYZER } from './infrastructure/proof-analyzer.token.js';
import { ProofVerificationRepository } from './infrastructure/proof-verification.repository.js';
import { SubmissionsRepository } from './infrastructure/submissions.repository.js';
import { VideoFrameExtractor } from './infrastructure/video-frame-extractor.js';
import { SubmissionsController } from './presentation/submissions.controller.js';

@Module({
  // ObjectStorageService, for reading the proof images forensics measures.
  imports: [MediaModule],
  controllers: [SubmissionsController],
  providers: [
    SubmissionsService,
    SubmissionsRepository,
    ProofVerificationService,
    ProofVerificationRepository,
    ProofProvenanceService,
    MediaForensicsService,
    VideoFrameExtractor,
    OpenAiProofAnalyzer,
    ClaudeProofAnalyzer,
    {
      // The one place a provider is named. Everything downstream depends on
      // the `ProofAnalyzer` interface, which is what lets the eval score both
      // providers over the same labelled history without touching the
      // pipeline — and makes switching a config change, not a rewrite.
      provide: PROOF_ANALYZER,
      inject: [ConfigService, OpenAiProofAnalyzer, ClaudeProofAnalyzer],
      useFactory: (
        config: ConfigService<Environment, true>,
        openai: OpenAiProofAnalyzer,
        anthropic: ClaudeProofAnalyzer,
      ) => (config.get('AI_VERIFICATION_PROVIDER', { infer: true }) === 'openai' ? openai : anthropic),
    },
  ],
  // ProofVerificationService is exported for the worker, which consumes
  // submission.created and runs the catch-up sweep.
  exports: [SubmissionsService, ProofVerificationService, ProofVerificationRepository],
})
export class SubmissionsModule {}
