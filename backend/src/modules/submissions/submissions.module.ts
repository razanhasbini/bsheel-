import { Module } from '@nestjs/common';
import { MediaModule } from '../media/media.module.js';
import { ProofVerificationService } from './application/proof-verification.service.js';
import { SubmissionsService } from './application/submissions.service.js';
import { ClaudeProofAnalyzer } from './infrastructure/claude-proof-analyzer.js';
import { ProofVerificationRepository } from './infrastructure/proof-verification.repository.js';
import { SubmissionsRepository } from './infrastructure/submissions.repository.js';
import { SubmissionsController } from './presentation/submissions.controller.js';

@Module({
  // ObjectStorageService, for reading the proof images the analyzer judges.
  imports: [MediaModule],
  controllers: [SubmissionsController],
  providers: [
    SubmissionsService,
    SubmissionsRepository,
    ProofVerificationService,
    ProofVerificationRepository,
    ClaudeProofAnalyzer,
  ],
  // ProofVerificationService is exported for the worker, which consumes
  // submission.created and runs the sweep.
  exports: [SubmissionsService, ProofVerificationService, ProofVerificationRepository],
})
export class SubmissionsModule {}
