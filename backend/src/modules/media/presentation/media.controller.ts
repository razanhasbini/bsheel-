import { Body, Controller, Delete, HttpCode, Param, Post } from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { MediaService } from '../application/media.service.js';
import { CompleteUploadDto, CreateUploadIntentDto, DeleteMediaObjectDto, SignMediaDto } from './media.dto.js';

class MediaIdParam { @IsUUID() id!: string; }

@ApiTags('media')
@Controller({ path: 'media', version: '1' })
export class MediaController {
  constructor(private readonly service: MediaService) {}

  @Post('upload-intents')
  createIntent(@CurrentUser() user: AuthUser, @Body() body: CreateUploadIntentDto) {
    return this.service.createIntent(user.id, body.clientRequestId, body.kind, body.contentType, body.sizeBytes);
  }

  @Post('uploads/complete')
  complete(@CurrentUser() user: AuthUser, @Body() body: CompleteUploadDto) {
    return this.service.complete(user.id, body.objectId);
  }

  @Post('sign')
  sign(@Body() body: SignMediaDto) { return this.service.sign(body.urls); }

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
