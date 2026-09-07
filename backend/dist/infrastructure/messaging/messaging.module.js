var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Global, Module } from '@nestjs/common';
import { MessagingQueueModule } from './messaging-queue.module.js';
import { OutboxPublisher } from './outbox.publisher.js';
let MessagingModule = class MessagingModule {
};
MessagingModule = __decorate([
    Global(),
    Module({
        imports: [MessagingQueueModule],
        providers: [OutboxPublisher],
        exports: [MessagingQueueModule],
    })
], MessagingModule);
export { MessagingModule };
//# sourceMappingURL=messaging.module.js.map