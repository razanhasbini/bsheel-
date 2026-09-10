import { Module } from '@nestjs/common';
import { DiscoveryRepository } from './infrastructure/discovery.repository.js';
import { HomeDiscoveryService } from './application/home-discovery.service.js';
import { QuestUnlockService } from './application/quest-unlock.service.js';
import { DiscoveryController } from './presentation/discovery.controller.js';

/**
 * Quest discovery: Home modules, Worth the Trip, trending and country pages.
 *
 * Separate from QuestsModule on purpose. Quests own the lifecycle — assign,
 * submit, expire — while this owns only reads that decide what a person is
 * shown. Keeping them apart is what stops a discovery query quietly growing
 * a write.
 */
@Module({
  controllers: [DiscoveryController],
  providers: [DiscoveryRepository, HomeDiscoveryService, QuestUnlockService],
  exports: [DiscoveryRepository, QuestUnlockService],
})
export class DiscoveryModule {}
