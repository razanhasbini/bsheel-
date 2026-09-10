import { Module } from '@nestjs/common';
import { GeofencingRepository } from './infrastructure/geofencing.repository.js';
import { GeofencingCallbackController } from './presentation/geofencing-callback.controller.js';

/**
 * Deliberately small and separate from AgentModule: the API process needs
 * the provider callback endpoint (CAMARA posts geofence events to it),
 * while the whole agent stack — OpenAI runner, CV adapters, queue
 * processors — only belongs in the worker. Both import this; neither
 * drags in the other.
 */
@Module({
  controllers: [GeofencingCallbackController],
  providers: [GeofencingRepository],
  exports: [GeofencingRepository],
})
export class GeofencingModule {}
