import { Body, Controller, Delete, Get, HttpCode, Param, Post, Put } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { CollabService } from '../application/collab.service.js';
import { CollabAssignmentParam, CollabCodeParam, CollabGroupParam, CollabVoteParam, CreateCollabGroupDto, JoinCollabGroupDto } from './collab.dto.js';

@ApiTags('collaboration')
@Controller({ path: 'collab', version: '1' })
export class CollabController {
  constructor(private readonly service: CollabService) {}

  @Post('groups')
  create(@CurrentUser() user: AuthUser, @Body() body: CreateCollabGroupDto) {
    return this.service.create(user.id, body.userQuestId, body.mode);
  }

  @Get('groups/preview/:code')
  preview(@Param() param: CollabCodeParam) { return this.service.preview(param.code); }

  @Post('groups/join')
  join(@CurrentUser() user: AuthUser, @Body() body: JoinCollabGroupDto) {
    return this.service.join(user.id, body.code, body.abandonActiveQuest);
  }

  @Get('assignments/:id')
  status(@CurrentUser() user: AuthUser, @Param() param: CollabAssignmentParam) {
    return this.service.status(user.id, param.id);
  }

  @HttpCode(204)
  @Post('assignments/:id/abandon')
  abandon(@CurrentUser() user: AuthUser, @Param() param: CollabAssignmentParam) {
    return this.service.abandon(user.id, param.id);
  }

  @HttpCode(204)
  @Delete('groups/:groupId/members/me')
  leave(@CurrentUser() user: AuthUser, @Param() param: CollabGroupParam) {
    return this.service.leave(user.id, param.groupId);
  }

  @HttpCode(204)
  @Put('groups/:groupId/votes/:submissionId')
  vote(@CurrentUser() user: AuthUser, @Param() param: CollabVoteParam) {
    return this.service.vote(user.id, param.groupId, param.submissionId);
  }

  @HttpCode(204)
  @Delete('groups/:groupId/votes/:submissionId')
  unvote(@CurrentUser() user: AuthUser, @Param() param: CollabVoteParam) {
    return this.service.unvote(user.id, param.groupId, param.submissionId);
  }
}
