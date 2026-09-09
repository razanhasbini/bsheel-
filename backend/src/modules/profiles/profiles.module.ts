import { Module } from '@nestjs/common';
import { ProfilesService } from './application/profiles.service.js';
import { StreakReminderService } from './application/streak-reminder.service.js';
import { ProfilesRepository } from './infrastructure/profiles.repository.js';
import { ProfilesController } from './presentation/profiles.controller.js';

@Module({
  controllers: [ProfilesController],
  providers: [ProfilesService, ProfilesRepository, StreakReminderService],
  // StreakReminderService is exported so the worker can schedule the sweep
  // without re-registering it, and so an e2e spec can run it directly.
  exports: [ProfilesService, StreakReminderService],
})
export class ProfilesModule {}

