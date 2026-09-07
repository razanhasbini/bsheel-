import { Module } from '@nestjs/common';
import { NotificationsService } from './application/notifications.service.js';
import { DeviceTokenCipher } from './infrastructure/device-token-cipher.js';
import { FirebasePushService } from './infrastructure/firebase-push.service.js';
import { NotificationsRepository } from './infrastructure/notifications.repository.js';
import { NotificationsController } from './presentation/notifications.controller.js';

@Module({
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsRepository, DeviceTokenCipher, FirebasePushService],
  exports: [DeviceTokenCipher, FirebasePushService],
})
export class NotificationsModule {}
