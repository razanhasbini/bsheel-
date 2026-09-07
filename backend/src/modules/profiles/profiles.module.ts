import { Module } from '@nestjs/common';
import { ProfilesService } from './application/profiles.service.js';
import { ProfilesRepository } from './infrastructure/profiles.repository.js';
import { ProfilesController } from './presentation/profiles.controller.js';

@Module({
  controllers: [ProfilesController],
  providers: [ProfilesService, ProfilesRepository],
  exports: [ProfilesService],
})
export class ProfilesModule {}

