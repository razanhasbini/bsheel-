import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
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
  pending(@Query() query: SubmissionListQuery) { return this.service.listPending(query.limit, query.offset); }

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
