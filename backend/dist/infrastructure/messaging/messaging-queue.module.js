var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let MessagingQueueModule = class MessagingQueueModule {
};
MessagingQueueModule = __decorate([
    Global(),
    Module({
        imports: [
            BullModule.forRootAsync({
                inject: [ConfigService],
                useFactory: (config) => ({
                    connection: { url: config.get('REDIS_URL', { infer: true }) },
                    prefix: `${config.get('REDIS_KEY_PREFIX', { infer: true })}bull`,
                }),
            }),
            BullModule.registerQueue({ name: 'domain-events' }),
        ],
        exports: [BullModule],
    })
], MessagingQueueModule);
export { MessagingQueueModule };
//# sourceMappingURL=messaging-queue.module.js.map