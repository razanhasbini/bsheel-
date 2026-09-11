import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnvironment } from '../../config/environment.js';
import { DatabaseModule } from '../../infrastructure/database/database.module.js';
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
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate: validateEnvironment }),
    DatabaseModule,
    SubmissionsModule,
  ],
})
export class ProofBackfillModule {}
