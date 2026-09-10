import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import type {
  AccessTokenPayload,
  AuthUser,
} from '../../common/auth/auth-user.js';
import type { Environment } from '../../config/environment.js';
import { AuthRepository } from '../../modules/auth/infrastructure/auth.repository.js';
import type { RealtimeDomainEvent } from './realtime-event.publisher.js';

interface AuthenticatedSocketData {
  user?: AuthUser;
}

@WebSocketGateway({ namespace: '/realtime', transports: ['websocket'] })
export class RealtimeGateway implements OnGatewayConnection {
  private readonly logger = new Logger(RealtimeGateway.name);

  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService<Environment, true>,
    private readonly auth: AuthRepository,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    try {
      const rawToken = this.connectionToken(client);
      const payload = await this.jwt.verifyAsync<AccessTokenPayload>(rawToken, {
        secret: this.config.get('JWT_ACCESS_SECRET', { infer: true }),
      });
      if (payload.type !== 'access') throw new Error('Wrong token type');
      const account = await this.auth.findActiveAccountById(payload.sub);
      if (!account || account.tokenVersion !== payload.tokenVersion) {
        throw new Error('Session revoked');
      }
      const user: AuthUser = {
        id: account.id,
        email: account.email,
        phoneVerified: account.phoneVerified,
        role: account.role,
        tokenVersion: account.tokenVersion,
      };
      (client.data as AuthenticatedSocketData).user = user;
      await client.join([`user:${user.id}`, 'feed']);
      if (user.role !== 'user') await client.join('admin');
      client.emit('ready', { userId: user.id });
    } catch {
      client.emit('auth.error', { code: 'INVALID_ACCESS_TOKEN' });
      client.disconnect(true);
    }
  }

  @SubscribeMessage('subscribe.post')
  async subscribePost(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { submissionId?: unknown },
  ): Promise<{ ok: true } | { ok: false; code: string }> {
    if (!(client.data as AuthenticatedSocketData).user)
      return { ok: false, code: 'UNAUTHENTICATED' };
    if (typeof body?.submissionId !== 'string' || !isUuid(body.submissionId)) {
      return { ok: false, code: 'INVALID_SUBMISSION_ID' };
    }
    await client.join(`post:${body.submissionId}`);
    return { ok: true };
  }

  @SubscribeMessage('unsubscribe.post')
  async unsubscribePost(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { submissionId?: unknown },
  ): Promise<{ ok: true } | { ok: false; code: string }> {
    if (typeof body?.submissionId !== 'string' || !isUuid(body.submissionId)) {
      return { ok: false, code: 'INVALID_SUBMISSION_ID' };
    }
    await client.leave(`post:${body.submissionId}`);
    return { ok: true };
  }

  broadcast(event: RealtimeDomainEvent): void {
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
      if (userId) this.server.to(`user:${userId}`).emit('domain.event', event);
      this.server.to(['feed', 'admin']).emit('domain.event', event);
      return;
    }
    if (event.type.startsWith('social.')) {
      if (submissionId)
        this.server.to(`post:${submissionId}`).emit('domain.event', event);
      if (userId) this.server.to(`user:${userId}`).emit('domain.event', event);
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

  private connectionToken(client: Socket): string {
    const authToken = client.handshake.auth?.token;
    if (typeof authToken === 'string' && authToken.length > 0) return authToken;
    const header = client.handshake.headers.authorization;
    if (typeof header === 'string' && header.startsWith('Bearer '))
      return header.slice(7);
    throw new Error('Missing token');
  }
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
}
