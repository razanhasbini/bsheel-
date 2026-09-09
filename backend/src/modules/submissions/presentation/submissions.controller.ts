import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsBooleanString, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { SubmissionsService } from '../application/submissions.service.js';
import { AppealSubmissionDto, CreateSubmissionDto, RejectSubmissionDto, ReviewSubmissionDto, SetVisibilityDto } from './submission.dto.js';

class SubmissionListQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 50;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
}

class SubmissionIdParam {
  @IsUUID() id!: string;
}

/// Drives both moderation views: the review queue (status=pending) and the
/// appeals queue (status=pending&appealed=true), plus the full history
/// (status=all, newest first).
class AdminSubmissionListQuery {
  @IsOptional() @IsIn(['pending', 'approved', 'rejected', 'all']) status: 'pending' | 'approved' | 'rejected' | 'all' = 'pending';
  @IsOptional() @IsBooleanString() appealed?: string;
  @IsOptional() @IsIn(['visible', 'hidden_from_feed', 'deleted', 'not_visible']) visibility?: 'visible' | 'hidden_from_feed' | 'deleted' | 'not_visible';
  @IsOptional() @IsIn(['asc', 'desc']) order: 'asc' | 'desc' = 'asc';
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 50;
  /// Kept for the clients that already pass it. Prefer `cursor`: the offset
  /// path degrades badly with depth (PERFORMANCE.md §5.2).
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
  /// Opaque keyset cursor from a previous page's `next_cursor`. Bound to the
  /// list that issued it, so one from another list is rejected.
  @IsOptional() @IsString() @MaxLength(1024) cursor?: string;
}

@ApiTags('submissions')
@Controller({ path: 'submissions', version: '1' })
export class SubmissionsController {
  constructor(private readonly service: SubmissionsService) {}

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() body: CreateSubmissionDto) { return this.service.create(user.id, body); }

  @Get('user/:id')
  listUser(@CurrentUser() user: AuthUser, @Param() params: SubmissionIdParam, @Query() query: SubmissionListQuery) {
    return this.service.listUser(params.id, user.id, query.limit, query.offset);
  }

  @Roles('moderator', 'super_admin')
  @Get('admin/pending')
  pending(@Query() query: AdminSubmissionListQuery) {
    return this.service.listForAdmin({
      status: 'pending',
      order: query.order,
      limit: query.limit,
      offset: query.offset,
      cursor: query.cursor,
    });
  }

  @Roles('moderator', 'super_admin')
  @Get('admin/review-queue')
  reviewQueue(@Query() query: AdminSubmissionListQuery) {
    return this.service.reviewQueue(query.limit, query.offset, query.cursor);
  }

  @Roles('moderator', 'super_admin')
  @Get('admin')
  adminList(@Query() query: AdminSubmissionListQuery) {
    return this.service.listForAdmin({
      status: query.status,
      appealed: query.appealed === undefined ? undefined : query.appealed === 'true',
      visibility: query.visibility,
      order: query.order,
      limit: query.limit,
      offset: query.offset,
      cursor: query.cursor,
    });
  }

  @Roles('moderator', 'super_admin')
  @Get('admin/:id')
  adminDetail(@Param() params: SubmissionIdParam) {
    return this.service.adminDetail(params.id);
  }

  @Get(':id')
  detail(@CurrentUser() user: AuthUser, @Param() params: SubmissionIdParam) { return this.service.detail(params.id, user.id); }

  @HttpCode(204)
  @Post(':id/appeal')
  appeal(@CurrentUser() user: AuthUser, @Param() params: SubmissionIdParam, @Body() body: AppealSubmissionDto) {
    return this.service.appeal(user.id, params.id, body.appealNote);
  }

  @HttpCode(204)
  @Roles('moderator', 'super_admin')
  @Post(':id/approve')
  approve(@CurrentUser() user: AuthUser, @Param() params: SubmissionIdParam, @Body() body: ReviewSubmissionDto) {
    return this.service.approve(user.id, params.id, body.reviewNote);
  }

  @HttpCode(204)
  @Roles('moderator', 'super_admin')
  @Post(':id/reject')
  reject(@CurrentUser() user: AuthUser, @Param() params: SubmissionIdParam, @Body() body: RejectSubmissionDto) {
    return this.service.reject(user.id, params.id, body.reviewNote);
  }

  @HttpCode(204)
  @Patch(':id/visibility')
  visibility(@CurrentUser() user: AuthUser, @Param() params: SubmissionIdParam, @Body() body: SetVisibilityDto) {
    return this.service.visibility(user.id, params.id, body.visibility);
  }
}
