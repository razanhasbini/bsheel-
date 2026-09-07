import { Module } from '@nestjs/common';
import { MediaModule } from '../media/media.module.js';
import { AccountService } from './application/account.service.js';
import { AccountRepository } from './infrastructure/account.repository.js';
import { AccountController } from './presentation/account.controller.js';

@Module({
  imports: [MediaModule],
  controllers: [AccountController],
  providers: [AccountService, AccountRepository],
})
export class AccountModule {}
