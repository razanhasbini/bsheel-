import { Module } from '@nestjs/common';
import { SubmissionsService } from './application/submissions.service.js';
import { SubmissionsRepository } from './infrastructure/submissions.repository.js';
import { SubmissionsController } from './presentation/submissions.controller.js';

@Module({
  controllers: [SubmissionsController],
  providers: [SubmissionsService, SubmissionsRepository],
  exports: [SubmissionsService],
})
export class SubmissionsModule {}

