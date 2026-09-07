var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { SubmissionsService } from './application/submissions.service.js';
import { SubmissionsRepository } from './infrastructure/submissions.repository.js';
import { SubmissionsController } from './presentation/submissions.controller.js';
let SubmissionsModule = class SubmissionsModule {
};
SubmissionsModule = __decorate([
    Module({
        controllers: [SubmissionsController],
        providers: [SubmissionsService, SubmissionsRepository],
        exports: [SubmissionsService],
    })
], SubmissionsModule);
export { SubmissionsModule };
//# sourceMappingURL=submissions.module.js.map