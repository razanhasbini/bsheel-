import { Module } from '@nestjs/common';
import { FeedService } from './application/feed.service.js';
import { FeedRepository } from './infrastructure/feed.repository.js';
import { FeedController } from './presentation/feed.controller.js';

@Module({ controllers: [FeedController], providers: [FeedService, FeedRepository] })
export class FeedModule {}

