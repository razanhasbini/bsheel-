import { Module } from '@nestjs/common';
import { MediaService } from './application/media.service.js';
import { MediaRepository } from './infrastructure/media.repository.js';
import { ObjectStorageService } from './infrastructure/object-storage.service.js';
import { MediaController } from './presentation/media.controller.js';

@Module({
  controllers: [MediaController],
  providers: [MediaService, MediaRepository, ObjectStorageService],
  exports: [MediaService, ObjectStorageService],
})
export class MediaModule {}
