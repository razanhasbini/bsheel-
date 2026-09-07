var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { MediaService } from './application/media.service.js';
import { MediaRepository } from './infrastructure/media.repository.js';
import { ObjectStorageService } from './infrastructure/object-storage.service.js';
import { MediaController } from './presentation/media.controller.js';
let MediaModule = class MediaModule {
};
MediaModule = __decorate([
    Module({
        controllers: [MediaController],
        providers: [MediaService, MediaRepository, ObjectStorageService],
        exports: [MediaService, ObjectStorageService],
    })
], MediaModule);
export { MediaModule };
//# sourceMappingURL=media.module.js.map