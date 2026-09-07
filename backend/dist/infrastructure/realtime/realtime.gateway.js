var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var RealtimeGateway_1;
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { ConnectedSocket, MessageBody, SubscribeMessage, WebSocketGateway, WebSocketServer, } from '@nestjs/websockets';
import { AuthRepository } from '../../modules/auth/infrastructure/auth.repository.js';
let RealtimeGateway = RealtimeGateway_1 = class RealtimeGateway {
    jwt;
    config;
    auth;
    logger = new Logger(RealtimeGateway_1.name);
    server;
    constructor(jwt, config, auth) {
        this.jwt = jwt;
        this.config = config;
        this.auth = auth;
    }
    async handleConnection(client) {
        try {
            const rawToken = this.connectionToken(client);
            const payload = await this.jwt.verifyAsync(rawToken, {
                secret: this.config.get('JWT_ACCESS_SECRET', { infer: true }),
            });
            if (payload.type !== 'access')
                throw new Error('Wrong token type');
            const account = await this.auth.findActiveAccountById(payload.sub);
            if (!account || account.tokenVersion !== payload.tokenVersion) {
                throw new Error('Session revoked');
            }
            const user = {
                id: account.id,
                email: account.email,
                role: account.role,
                tokenVersion: account.tokenVersion,
            };
            client.data.user = user;
            await client.join([`user:${user.id}`, 'feed']);
            if (user.role !== 'user')
                await client.join('admin');
            client.emit('ready', { userId: user.id });
        }
        catch {
            client.emit('auth.error', { code: 'INVALID_ACCESS_TOKEN' });
            client.disconnect(true);
        }
    }
    async subscribePost(client, body) {
        if (!client.data.user)
            return { ok: false, code: 'UNAUTHENTICATED' };
        if (typeof body?.submissionId !== 'string' || !isUuid(body.submissionId)) {
            return { ok: false, code: 'INVALID_SUBMISSION_ID' };
        }
        await client.join(`post:${body.submissionId}`);
        return { ok: true };
    }
    async unsubscribePost(client, body) {
        if (typeof body?.submissionId !== 'string' || !isUuid(body.submissionId)) {
            return { ok: false, code: 'INVALID_SUBMISSION_ID' };
        }
        await client.leave(`post:${body.submissionId}`);
        return { ok: true };
    }
    broadcast(event) {
        const submissionId = stringValue(event.data.submissionId);
        const userId = stringValue(event.data.userId);
        const targetUserId = stringValue(event.data.targetUserId);
        const profileId = stringValue(event.data.profileId);
        if (event.type.startsWith('notification.') && userId) {
            this.server.to(`user:${userId}`).emit('domain.event', event);
            return;
        }
        if (event.type.startsWith('quest.') && userId) {
            this.server.to(`user:${userId}`).emit('domain.event', event);
            return;
        }
        if (event.type.startsWith('submission.')) {
            if (submissionId)
                this.server.to(`post:${submissionId}`).emit('domain.event', event);
            if (userId)
                this.server.to(`user:${userId}`).emit('domain.event', event);
            this.server.to(['feed', 'admin']).emit('domain.event', event);
            return;
        }
        if (event.type.startsWith('social.')) {
            if (submissionId)
                this.server.to(`post:${submissionId}`).emit('domain.event', event);
            if (userId)
                this.server.to(`user:${userId}`).emit('domain.event', event);
            if (targetUserId)
                this.server.to(`user:${targetUserId}`).emit('domain.event', event);
            this.server.to('feed').emit('domain.event', event);
            return;
        }
        if (event.type.startsWith('report.')) {
            this.server.to('admin').emit('domain.event', event);
            return;
        }
        if (event.type === 'profile.updated' && profileId) {
            this.server.to(['feed', `user:${profileId}`]).emit('domain.event', event);
            return;
        }
        if (event.type.startsWith('admin.')) {
            this.server.to('admin').emit('domain.event', event);
        }
    }
    connectionToken(client) {
        const authToken = client.handshake.auth?.token;
        if (typeof authToken === 'string' && authToken.length > 0)
            return authToken;
        const header = client.handshake.headers.authorization;
        if (typeof header === 'string' && header.startsWith('Bearer '))
            return header.slice(7);
        throw new Error('Missing token');
    }
};
__decorate([
    WebSocketServer(),
    __metadata("design:type", Function)
], RealtimeGateway.prototype, "server", void 0);
__decorate([
    SubscribeMessage('subscribe.post'),
    __param(0, ConnectedSocket()),
    __param(1, MessageBody()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Function, Object]),
    __metadata("design:returntype", Promise)
], RealtimeGateway.prototype, "subscribePost", null);
__decorate([
    SubscribeMessage('unsubscribe.post'),
    __param(0, ConnectedSocket()),
    __param(1, MessageBody()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Function, Object]),
    __metadata("design:returntype", Promise)
], RealtimeGateway.prototype, "unsubscribePost", null);
RealtimeGateway = RealtimeGateway_1 = __decorate([
    WebSocketGateway({ namespace: '/realtime', transports: ['websocket'] }),
    __metadata("design:paramtypes", [JwtService,
        ConfigService,
        AuthRepository])
], RealtimeGateway);
export { RealtimeGateway };
function stringValue(value) {
    return typeof value === 'string' ? value : undefined;
}
function isUuid(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
//# sourceMappingURL=realtime.gateway.js.map