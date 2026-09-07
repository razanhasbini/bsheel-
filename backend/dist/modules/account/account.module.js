var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { MediaModule } from '../media/media.module.js';
import { AccountService } from './application/account.service.js';
import { AccountRepository } from './infrastructure/account.repository.js';
import { AccountController } from './presentation/account.controller.js';
let AccountModule = class AccountModule {
};
AccountModule = __decorate([
    Module({
        imports: [MediaModule],
        controllers: [AccountController],
        providers: [AccountService, AccountRepository],
    })
], AccountModule);
export { AccountModule };
//# sourceMappingURL=account.module.js.map