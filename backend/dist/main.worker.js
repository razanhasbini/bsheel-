import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { Logger as PinoLogger } from 'nestjs-pino';
import { WorkerModule } from './worker.module.js';
const application = await NestFactory.createApplicationContext(WorkerModule, { bufferLogs: true });
application.useLogger(application.get(PinoLogger));
application.enableShutdownHooks();
Logger.log('Bsheel domain-event worker is ready', 'WorkerBootstrap');
//# sourceMappingURL=main.worker.js.map