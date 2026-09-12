import { Module } from '@nestjs/common';
import { BrandedExportService } from './application/branded-export.service.js';
import { MediaService } from './application/media.service.js';
import { MediaReclaimService } from './application/media-reclaim.service.js';
import { BrandedExportRepository } from './infrastructure/branded-export.repository.js';
import { MediaRepository } from './infrastructure/media.repository.js';
import { ObjectStorageService } from './infrastructure/object-storage.service.js';
import { MediaController } from './presentation/media.controller.js';

@Module({
  controllers: [MediaController],
  providers: [
    MediaService,
    MediaReclaimService,
    MediaRepository,
    ObjectStorageService,
    BrandedExportRepository,
    BrandedExportService,
  ],
  exports: [MediaService, MediaReclaimService, ObjectStorageService, BrandedExportRepository],
})
export class MediaModule {}
