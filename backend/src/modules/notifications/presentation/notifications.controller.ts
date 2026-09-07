import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { NotificationsService } from '../application/notifications.service.js';
import { DeleteDeviceTokenDto, NotificationListQueryDto, RegisterDeviceTokenDto } from './notifications.dto.js';

class NotificationIdParam { @IsUUID() id!: string; }

@ApiTags('notifications')
@Controller({ path: 'notifications', version: '1' })
export class NotificationsController {
  constructor(private readonly service: NotificationsService) {}

  @Get()
  list(@CurrentUser() user: AuthUser, @Query() query: NotificationListQueryDto) {
    return this.service.list(user.id, query.limit, query.cursor);
  }

  @Get('unread-count')
  unreadCount(@CurrentUser() user: AuthUser) { return this.service.unreadCount(user.id); }

  @HttpCode(204)
  @Patch(':id/read')
  markRead(@CurrentUser() user: AuthUser, @Param() param: NotificationIdParam) {
    return this.service.markRead(user.id, param.id);
  }

  @Patch('read-all')
  markAllRead(@CurrentUser() user: AuthUser) { return this.service.markAllRead(user.id); }

  @Post('devices')
  registerDevice(@CurrentUser() user: AuthUser, @Body() body: RegisterDeviceTokenDto) {
    return this.service.registerDevice(user.id, body.token, body.platform);
  }

  @HttpCode(204)
  @Delete('devices')
  deleteDevice(@CurrentUser() user: AuthUser, @Body() body: DeleteDeviceTokenDto) {
    return this.service.deleteDevice(user.id, body.token);
  }
}
