var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { QuestsService } from './application/quests.service.js';
import { QuestsRepository } from './infrastructure/quests.repository.js';
import { QuestsController } from './presentation/quests.controller.js';
let QuestsModule = class QuestsModule {
};
QuestsModule = __decorate([
    Module({
        controllers: [QuestsController],
        providers: [QuestsService, QuestsRepository],
        exports: [QuestsService],
    })
], QuestsModule);
export { QuestsModule };
//# sourceMappingURL=quests.module.js.map