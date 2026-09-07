import { Module } from '@nestjs/common';
import { CollabService } from './application/collab.service.js';
import { CollabRepository } from './infrastructure/collab.repository.js';
import { CollabController } from './presentation/collab.controller.js';

@Module({ controllers: [CollabController], providers: [CollabService, CollabRepository] })
export class CollabModule {}
