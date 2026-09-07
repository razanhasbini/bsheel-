import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthModule } from '../../modules/auth/auth.module.js';
import { RealtimeEventSubscriber } from './realtime-event.subscriber.js';
import { RealtimeGateway } from './realtime.gateway.js';

@Module({
  imports: [JwtModule.register({}), AuthModule],
  providers: [RealtimeGateway, RealtimeEventSubscriber],
})
export class RealtimeModule {}
