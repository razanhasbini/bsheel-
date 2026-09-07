import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { AccountService } from '../application/account.service.js';
import { RequestDeletionDto } from './account.dto.js';

@ApiTags('account privacy')
@Controller({ path: 'account', version: '1' })
export class AccountController {
  constructor(private readonly service: AccountService) {}
  @Post('exports') requestExport(@CurrentUser() user: AuthUser) { return this.service.requestExport(user.id); }
  @Get('exports') exports(@CurrentUser() user: AuthUser) { return this.service.exports(user.id); }
  @HttpCode(202) @Post('deletion')
  requestDeletion(@CurrentUser() user: AuthUser, @Body() _body: RequestDeletionDto) { return this.service.requestDeletion(user.id); }
}
