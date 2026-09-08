import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Public } from '../../../common/auth/public.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import { AdminService } from '../application/admin.service.js';
import { AdminListQueryDto, ConfigKeyParam, CreateUserDto, ForceResetPasswordDto, InjectQuestDto, RemovePostDto, ReportsQueryDto, ReviewReportDto, SendNotificationDto, SetAccountStatusDto, SetAdminRoleDto, SetConfigDto, SetQotdDto, SetUserXpDto,
  UpdateUserProfileDto, SuggestionStatusDto, SuggestionsQueryDto, UserIdParam } from './admin.dto.js';

@ApiTags('configuration')
@Controller({ path: 'config', version: '1' })
export class PublicConfigController {
  constructor(private readonly service: AdminService) {}
  @Public() @Get() publicConfig() { return this.service.publicConfig(); }
}

@ApiTags('admin')
@Roles('moderator', 'super_admin')
@Controller({ path: 'admin', version: '1' })
export class AdminController {
  constructor(private readonly service: AdminService) {}

  @Get('me') me(@CurrentUser() user: AuthUser) { return this.service.me(user.id); }
  @Get('stats') stats() { return this.service.stats(); }
  @Roles('super_admin') @Get('xp-audit')
  xpAudit(@Query() query: AdminListQueryDto) { return this.service.xpAudit(query.limit, query.offset); }
  @Get('users') users(@Query() query: AdminListQueryDto) { return this.service.users(query.q, query.limit, query.offset); }
  @Throttle({ default: { limit: 10, ttl: 60_000 } }) @Post('users')
  createUser(@CurrentUser() user: AuthUser, @Body() body: CreateUserDto) {
    return this.service.createUser(user.id, body);
  }
  @Roles('super_admin') @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @HttpCode(202) @Delete('users/:id')
  deleteUser(@CurrentUser() user: AuthUser, @Param() param: UserIdParam) {
    return this.service.deleteUser(user.id, param.id);
  }
  @Roles('super_admin') @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @HttpCode(204) @Put('users/:id/role')
  setAdminRole(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: SetAdminRoleDto) {
    return this.service.setAdminRole(user.id, param.id, body.role);
  }
  @Roles('super_admin') @Throttle({ default: { limit: 3, ttl: 60_000 } })
  @HttpCode(204) @Post('users/:id/password')
  forceResetPassword(
    @CurrentUser() user: AuthUser,
    @Param() param: UserIdParam,
    @Body() body: ForceResetPasswordDto,
  ) {
    return this.service.forceResetPassword(user.id, param.id, body.newPassword);
  }
  @Throttle({ default: { limit: 3, ttl: 60_000 } })
  @HttpCode(202) @Post('users/:id/password-recovery')
  requestPasswordRecovery(@CurrentUser() user: AuthUser, @Param() param: UserIdParam) {
    return this.service.requestPasswordRecovery(user.id, param.id);
  }
  @Roles('super_admin') @HttpCode(204) @Patch('users/:id/status')
  setStatus(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: SetAccountStatusDto) { return this.service.setStatus(user.id, param.id, body.status, body.reason); }
  @Roles('super_admin') @HttpCode(204) @Patch('users/:id/profile')
  updateUserProfile(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: UpdateUserProfileDto) {
    return this.service.updateUserProfile(user.id, param.id, body);
  }

  @Roles('super_admin') @HttpCode(204) @Patch('users/:id/xp')
  setXp(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: SetUserXpDto) { return this.service.setXp(user.id, param.id, body.xp, body.level, body.questsCompleted, body.reason); }

  @Get('reports') reports(@Query() query: ReportsQueryDto) { return this.service.reports(query.status, query.limit, query.offset); }
  @HttpCode(204) @Patch('reports/:id')
  reviewReport(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: ReviewReportDto) { return this.service.reviewReport(user.id, param.id, body.status, body.adminNote); }

  @HttpCode(204) @Post('submissions/:id/remove')
  removePost(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: RemovePostDto) {
    return this.service.removePost(user.id, param.id, body.reason);
  }

  @Get('injections') injections(@Query() query: AdminListQueryDto) { return this.service.injections(query.limit, query.offset); }
  @Post('injections') inject(@CurrentUser() user: AuthUser, @Body() body: InjectQuestDto) { return this.service.inject(user.id, body); }
  @HttpCode(204) @Delete('injections/:id') cancelInjection(@CurrentUser() user: AuthUser, @Param() param: UserIdParam) { return this.service.cancelInjection(user.id, param.id); }

  @Post('notifications') notify(@CurrentUser() user: AuthUser, @Body() body: SendNotificationDto) { return this.service.notify(user.id, body.targetUserId, body.title, body.body, body.type); }

  /// Recent automatic notifications, so the admin dashboard can show what
  /// the system has been sending. Announcements are excluded because they
  /// are authored by admins and listed on their own page.
  @Get('notifications') notifications(@Query() query: AdminListQueryDto) {
    return this.service.notifications(query.limit, query.offset);
  }

  @Roles('super_admin') @Get('config') config() { return this.service.config(); }
  @Roles('super_admin') @Put('config/:key')
  setConfig(@CurrentUser() user: AuthUser, @Param() param: ConfigKeyParam, @Body() body: SetConfigDto) { return this.service.setConfig(user.id, param.key, body.value, body.description, body.isPublic); }

  @Get('qotd') qotd(@Query() query: AdminListQueryDto) { return this.service.qotd(query.limit, query.offset); }
  @Put('qotd') setQotd(@CurrentUser() user: AuthUser, @Body() body: SetQotdDto) { return this.service.setQotd(user.id, body); }
  @HttpCode(204) @Delete('qotd/:id') deleteQotd(@Param() param: UserIdParam) { return this.service.deleteQotd(param.id); }

  @Get('waitlist') waitlist(@Query() query: AdminListQueryDto) { return this.service.waitlist(query.limit, query.offset); }
  @Get('suggestions') suggestions(@Query() query: SuggestionsQueryDto) { return this.service.suggestions(query.status, query.limit, query.offset); }
  @Patch('suggestions/:id') reviewSuggestion(@CurrentUser() user: AuthUser, @Param() param: UserIdParam, @Body() body: SuggestionStatusDto) { return this.service.reviewSuggestion(user.id, param.id, body.status, body.xpReward, body.durationHours); }
}
