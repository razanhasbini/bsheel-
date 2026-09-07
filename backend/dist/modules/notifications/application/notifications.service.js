var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { createHash } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { decodeChronologicalCursor, encodeChronologicalCursor } from '../../../common/pagination/cursor.js';
import { DeviceTokenCipher } from '../infrastructure/device-token-cipher.js';
import { NotificationsRepository } from '../infrastructure/notifications.repository.js';
let NotificationsService = class NotificationsService {
    repository;
    cipher;
    constructor(repository, cipher) {
        this.repository = repository;
        this.cipher = cipher;
    }
    async list(userId, limit, rawCursor) {
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
    async unreadCount(userId) {
        return { count: await this.repository.unreadCount(userId) };
    }
    markRead(userId, notificationId) {
        return this.repository.markRead(userId, notificationId);
    }
    async markAllRead(userId) {
        return { updated: await this.repository.markAllRead(userId) };
    }
    async registerDevice(userId, token, platform) {
        const protectedToken = this.cipher.protect(token);
        return { id: await this.repository.upsertDeviceToken(userId, protectedToken.hash, protectedToken.encrypted, platform) };
    }
    deleteDevice(userId, token) {
        const hash = createHash('sha256').update(token, 'utf8').digest();
        return this.repository.deleteDeviceToken(userId, hash);
    }
};
NotificationsService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [NotificationsRepository,
        DeviceTokenCipher])
], NotificationsService);
export { NotificationsService };
//# sourceMappingURL=notifications.service.js.map