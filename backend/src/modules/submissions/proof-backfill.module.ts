import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnvironment } from '../../config/environment.js';
import { DatabaseModule } from '../../infrastructure/database/database.module.js';
import { MessagingQueueModule } from '../../infrastructure/messaging/messaging-queue.module.js';
import { SubmissionsModule } from './submissions.module.js';

/**
 * The smallest graph that can score a submission, for `npm run proof:backfill`.
 *
 * Deliberately not WorkerModule. That registers every BullMQ processor, so a
 * one-off command would start consuming the live queues — quest maintenance,
 * notification delivery, the agent pipeline — for as long as it ran, on
 * whatever database it was pointed at. A CLI that quietly becomes a second
 * worker is not a CLI.
 *
 * `DatabaseModule` is `@Global`, and SubmissionsModule brings the analyzer,
 * forensics and object storage with it, so this is the whole of it.
 *
 * `MessagingQueueModule` registers the queue *handles* — producers, not
 * workers — which is the distinction that keeps the rule above true. Without
 * it this graph cannot be built at all: object storage arrives with
 * MediaModule, and MediaModule's branded-export service injects a queue.
 * Registering one creates no consumer and starts no processor, so nothing
 * here picks work off a live queue; it only makes the token resolvable.
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate: validateEnvironment }),
    DatabaseModule,
    MessagingQueueModule,
    SubmissionsModule,
  ],
})
export class ProofBackfillModule {}
