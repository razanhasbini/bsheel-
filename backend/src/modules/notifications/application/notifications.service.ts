import { createHash } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { decodeChronologicalCursor, encodeChronologicalCursor } from '../../../common/pagination/cursor.js';
import { DeviceTokenCipher } from '../infrastructure/device-token-cipher.js';
import { NotificationsRepository } from '../infrastructure/notifications.repository.js';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly repository: NotificationsRepository,
    private readonly cipher: DeviceTokenCipher,
  ) {}

  async list(userId: string, limit: number, rawCursor?: string) {
    const rows = await this.repository.list(userId, limit, decodeChronologicalCursor(rawCursor));
    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    const last = items.at(-1);
    return {
      items,
      nextCursor: hasMore && last
        ? encodeChronologicalCursor({ createdAt: new Date(last.created_at).toISOString(), id: last.id })
        : null,
    };
  }

  async unreadCount(userId: string) {
    return { count: await this.repository.unreadCount(userId) };
  }

  markRead(userId: string, notificationId: string) {
    return this.repository.markRead(userId, notificationId);
  }

  async markAllRead(userId: string) {
    return { updated: await this.repository.markAllRead(userId) };
  }

  async registerDevice(userId: string, token: string, platform: string) {
    const protectedToken = this.cipher.protect(token);
    return { id: await this.repository.upsertDeviceToken(userId, protectedToken.hash, protectedToken.encrypted, platform) };
  }

  deleteDevice(userId: string, token: string) {
    const hash = createHash('sha256').update(token, 'utf8').digest();
    return this.repository.deleteDeviceToken(userId, hash);
  }
}
