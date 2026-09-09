import { Module } from '@nestjs/common';
import { MapController } from './presentation/map.controller.js';
import { MapRepository } from './infrastructure/map.repository.js';
import { MapService } from './application/map.service.js';

@Module({ controllers:[MapController], providers:[MapRepository,MapService] })
export class MapModule {}
