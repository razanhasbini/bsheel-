import { Global, Module } from '@nestjs/common';
import { MessagingQueueModule } from './messaging-queue.module.js';
import { OutboxPublisher } from './outbox.publisher.js';

@Global()
@Module({
  imports: [MessagingQueueModule],
  providers: [OutboxPublisher],
  exports: [MessagingQueueModule],
})
export class MessagingModule {}
