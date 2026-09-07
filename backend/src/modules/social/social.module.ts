import { Module } from '@nestjs/common';
import { SocialService } from './application/social.service.js';
import { SocialRepository } from './infrastructure/social.repository.js';
import { SocialController } from './presentation/social.controller.js';

@Module({ controllers: [SocialController], providers: [SocialService, SocialRepository] })
export class SocialModule {}

