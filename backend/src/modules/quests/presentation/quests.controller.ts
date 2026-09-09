import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { QuestsService } from '../application/quests.service.js';
import { BulkCreateQuestsDto, CreateQuestDto, DeleteAllQuestsDto, FollowingActiveQueryDto, QuestHistoryQueryDto, QuestIdDto, QuestPickerQueryDto, UpdateQuestDto, UserQuestIdDto } from './quest.dto.js';

class AdminAssignQuestDto {
  @IsUUID() userId!: string;
  @IsUUID() questId!: string;
}

/// Validates a `:id` path segment as a UUID before it reaches the service.
///
/// Without this, `GET /quests/rerolls` matched `@Get(':id')`, passed the
/// literal string "rerolls" into a uuid-typed query, and Postgres raised
/// 22P02 — surfacing as a 500 and an error-level log for what is really a
/// client sending a bad id. Any non-UUID id did the same.
class QuestIdParam {
  @IsUUID() id!: string;
}

@ApiTags('quests')
@Controller({ path: 'quests', version: '1' })
export class QuestsController {
  constructor(private readonly service: QuestsService) {}

  @Get('active')
  @ApiOperation({ summary: "Get the caller's assigned or submitted quest" })
  active(@CurrentUser() user: AuthUser) { return this.service.active(user.id); }

  @Get('history')
  history(@CurrentUser() user: AuthUser, @Query() query: QuestHistoryQueryDto) {
    return this.service.history(user.id, query.limit, query.offset);
  }

  @Get('picker')
  picker(@CurrentUser() user: AuthUser, @Query() query: QuestPickerQueryDto) { return this.service.picker(user.id, query.count); }

  @Get('quest-of-the-day')
  qotd() { return this.service.qotd(); }

  @Get('following-active')
  followingActive(@CurrentUser() user: AuthUser, @Query() query: FollowingActiveQueryDto) {
    return this.service.followingActive(user.id, query.limit);
  }

  @Get('rerolls/remaining')
  async rerollsRemaining(@CurrentUser() user: AuthUser) { return { remaining: await this.service.rerollsRemaining(user.id) }; }

  @Post('rerolls')
  async reroll(@CurrentUser() user: AuthUser) { return { remaining: await this.service.reroll(user.id) }; }

  @Post('assign')
  assign(@CurrentUser() user: AuthUser, @Body() body: QuestIdDto) { return this.service.assign(user.id, body.questId); }

  @HttpCode(204)
  @Post('expire')
  expire(@CurrentUser() user: AuthUser, @Body() body: UserQuestIdDto) { return this.service.expire(user.id, body.userQuestId); }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param() param: QuestIdParam) { return this.service.getQuest(param.id, user.id); }

  @Roles('moderator', 'super_admin')
  @Post('admin/assign')
  assignForUser(@Body() body: AdminAssignQuestDto) {
    return this.service.assignForUser(body.userId, body.questId);
  }

  @Roles('super_admin')
  @Get('admin/all')
  allAdmin() { return this.service.listAll(); }

  @Roles('super_admin')
  @Post('admin')
  create(@CurrentUser() user: AuthUser, @Body() body: CreateQuestDto) { return this.service.create(body, user.id); }

  @Roles('super_admin')
  @Post('admin/bulk')
  createBulk(@CurrentUser() user: AuthUser, @Body() body: BulkCreateQuestsDto) {
    return this.service.createBulk(body.quests, user.id);
  }

  @Roles('super_admin')
  @Patch('admin/:id')
  update(@Param() param: QuestIdParam, @Body() body: UpdateQuestDto) { return this.service.update(param.id, body); }

  @Roles('super_admin')
  @HttpCode(204)
  @Delete('admin/:id')
  delete(@CurrentUser() user: AuthUser, @Param() param: QuestIdParam) {
    return this.service.delete(param.id, user.id);
  }

  @Roles('super_admin')
  @Delete('admin')
  deleteAll(@CurrentUser() user: AuthUser, @Body() body: DeleteAllQuestsDto) {
    return this.service.deleteAll(user.id, body.confirmation);
  }
}
