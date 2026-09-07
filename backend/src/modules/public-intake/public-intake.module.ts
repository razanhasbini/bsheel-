import { Module } from '@nestjs/common';
import { PublicIntakeService } from './application/public-intake.service.js';
import { PublicIntakeRepository } from './infrastructure/public-intake.repository.js';
import { PublicIntakeController } from './presentation/public-intake.controller.js';

@Module({ controllers: [PublicIntakeController], providers: [PublicIntakeService, PublicIntakeRepository] })
export class PublicIntakeModule {}
