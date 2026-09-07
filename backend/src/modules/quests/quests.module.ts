import { Module } from '@nestjs/common';
import { QuestsService } from './application/quests.service.js';
import { QuestsRepository } from './infrastructure/quests.repository.js';
import { QuestsController } from './presentation/quests.controller.js';

@Module({
  controllers: [QuestsController],
  providers: [QuestsService, QuestsRepository],
  exports: [QuestsService],
})
export class QuestsModule {}

