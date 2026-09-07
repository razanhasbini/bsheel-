import { Body, Controller, Delete, Get, HttpCode, Param, Post, Put, Query } from '@nestjs/common';
import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { SocialService } from '../application/social.service.js';
import { AddCommentDto, BlockUserDto, ReportContentDto, VoteDto } from './social.dto.js';

class IdParam { @IsUUID() id!: string; }
class ListQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
}
class ConnectionQuery extends ListQuery {
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  followers = true;
}

@ApiTags('social')
@Controller({ path: 'social', version: '1' })
export class SocialController {
  constructor(private readonly service: SocialService) {}

  @Get('posts/:id/vote') getVote(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.getVote(u.id, p.id); }
  @Put('posts/:id/vote') vote(@CurrentUser() u: AuthUser, @Param() p: IdParam, @Body() b: VoteDto) { return this.service.vote(u.id, p.id, b.type); }
  @HttpCode(204) @Delete('posts/:id/vote') removeVote(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.removeVote(u.id, p.id); }

  @Get('posts/:id/comments') comments(@Param() p: IdParam, @Query() q: ListQuery) { return this.service.comments(p.id, q.limit, q.offset); }
  @Post('posts/:id/comments') addComment(@CurrentUser() u: AuthUser, @Param() p: IdParam, @Body() b: AddCommentDto) { return this.service.addComment(u.id, p.id, b.body, b.parentId); }
  @HttpCode(204) @Delete('comments/:id') deleteComment(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.deleteComment(u.id, u.role, p.id); }

  @Get('users/:id/following') async isFollowing(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return { following: await this.service.isFollowing(u.id, p.id) }; }
  @Post('users/:id/follow') async follow(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return { id: await this.service.follow(u.id, p.id) }; }
  @HttpCode(204) @Delete('users/:id/follow') unfollow(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.unfollow(u.id, p.id); }
  @Get('users/:id/connections') connections(@Param() p: IdParam, @Query() q: ConnectionQuery) { return this.service.connections(p.id, q.followers, q.limit, q.offset); }
  @Get('users/:id/follow-counts') counts(@Param() p: IdParam) { return this.service.counts(p.id); }

  @HttpCode(204) @Post('users/:id/block') block(@CurrentUser() u: AuthUser, @Param() p: IdParam, @Body() b: BlockUserDto) { return this.service.block(u.id, p.id, b.reason); }
  @HttpCode(204) @Delete('users/:id/block') unblock(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.unblock(u.id, p.id); }
  @Get('blocked-users') blockedUsers(@CurrentUser() u: AuthUser, @Query() q: ListQuery) { return this.service.blockedUsers(u.id, q.limit, q.offset); }
  @Post('reports') async report(@CurrentUser() u: AuthUser, @Body() b: ReportContentDto) { return { id: await this.service.report(u.id, b.reportedType, b.reportedId, b.reason) }; }

  @Get('saved/posts') savedPosts(@CurrentUser() u: AuthUser, @Query() q: ListQuery) { return this.service.savedPosts(u.id, q.limit, q.offset); }
  @Get('saved/posts/:id') async isPostSaved(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return { saved: await this.service.isPostSaved(u.id, p.id) }; }
  @HttpCode(204) @Put('saved/posts/:id') savePost(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.savePost(u.id, p.id, true); }
  @HttpCode(204) @Delete('saved/posts/:id') unsavePost(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.savePost(u.id, p.id, false); }
  @Get('saved/quests') savedQuests(@CurrentUser() u: AuthUser, @Query() q: ListQuery) { return this.service.savedQuests(u.id, q.limit, q.offset); }
  @Get('saved/quests/:id') async isQuestSaved(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return { saved: await this.service.isQuestSaved(u.id, p.id) }; }
  @HttpCode(204) @Put('saved/quests/:id') saveQuest(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.saveQuest(u.id, p.id, true); }
  @HttpCode(204) @Delete('saved/quests/:id') unsaveQuest(@CurrentUser() u: AuthUser, @Param() p: IdParam) { return this.service.saveQuest(u.id, p.id, false); }
}
