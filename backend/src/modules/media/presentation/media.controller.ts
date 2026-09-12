import { Body, Controller, Delete, Get, HttpCode, Param, Post } from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { BrandedExportService } from '../application/branded-export.service.js';
import { MediaService } from '../application/media.service.js';
import { CompleteUploadDto, CreateUploadIntentDto, DeleteMediaObjectDto, SignMediaDto } from './media.dto.js';

class MediaIdParam { @IsUUID() id!: string; }
class RequestBrandedExportDto { @IsUUID() submissionId!: string; }

@ApiTags('media')
@Controller({ path: 'media', version: '1' })
export class MediaController {
  constructor(
    private readonly service: MediaService,
    private readonly brandedExports: BrandedExportService,
  ) {}

  /// Asks the worker to render this post's video with the Bsheel band
  /// burned in (0050). Idempotent per post; a failed render is re-queued.
  @Post('branded-exports')
  @HttpCode(202)
  @ApiOperation({ summary: "Queue a render of a video post with the Bsheel quest/date/place band burned in" })
  requestBrandedExport(@CurrentUser() user: AuthUser, @Body() body: RequestBrandedExportDto) {
    return this.brandedExports.request(user.id, body.submissionId);
  }

  @Get('branded-exports/:id')
  @ApiOperation({ summary: 'Status of a branded render, with a signed download URL once ready' })
  brandedExport(@CurrentUser() user: AuthUser, @Param() param: MediaIdParam) {
    return this.brandedExports.status(user.id, param.id);
  }

  @Post('upload-intents')
  createIntent(@CurrentUser() user: AuthUser, @Body() body: CreateUploadIntentDto) {
    return this.service.createIntent(user.id, body.clientRequestId, body.kind, body.contentType, body.sizeBytes);
  }

  @Post('uploads/complete')
  complete(@CurrentUser() user: AuthUser, @Body() body: CompleteUploadDto) {
    return this.service.complete(user.id, body.objectId);
  }

  // Takes the caller: signing is an authorisation decision, not a URL
  // transformation. Without the identity the service cannot check anything,
  // which is how this endpoint came to sign any key for anyone.
  @Post('sign')
  sign(@CurrentUser() user: AuthUser, @Body() body: SignMediaDto) {
    const isModerator = user.role === 'moderator' || user.role === 'super_admin';
    return this.service.sign(user.id, isModerator, body.urls);
  }

  @HttpCode(204)
  @Delete('objects')
  deleteByKey(@CurrentUser() user: AuthUser, @Body() body: DeleteMediaObjectDto) {
    return this.service.deleteByKey(user.id, body.key);
  }

  @HttpCode(204)
  @Delete(':id')
  delete(@CurrentUser() user: AuthUser, @Param() param: MediaIdParam) {
    return this.service.delete(user.id, param.id);
  }
}
