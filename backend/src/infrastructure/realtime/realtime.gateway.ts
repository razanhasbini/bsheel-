import { Logger } from '@nestjs/common';
import type { OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
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

/**
 * How often live sockets are re-checked against `users.token_version`.
 *
 * Revocation used to be a connect-time check only, so a socket opened before
 * a logout, ban or password reset kept streaming events for as long as it
 * stayed open. Seven different statements bump `token_version`; sweeping the
 * connected set covers all of them, including any added later, without each
 * call site having to remember to signal the gateway.
 */
const REVALIDATE_INTERVAL_MS = 30_000;

@WebSocketGateway({ namespace: '/realtime', transports: ['websocket'] })
export class RealtimeGateway
  implements
    OnGatewayConnection,
    OnGatewayDisconnect,
    OnApplicationBootstrap,
    OnModuleDestroy
{
  private readonly logger = new Logger(RealtimeGateway.name);

  /**
   * Sockets this process is serving.
   *
   * Tracked explicitly rather than read back off the server: with a namespace
   * configured, what `@WebSocketServer()` hands over differs between a plain
   * and an adapter-backed setup, and a sweep that silently enumerates zero
   * sockets would look exactly like a sweep that found nothing to revoke.
   * Each instance owns its own connections, so instance-local is also the
   * correct scope.
   */
  private readonly connected = new Set<Socket>();
  private revalidateTimer?: NodeJS.Timeout;

  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService<Environment, true>,
    private readonly auth: AuthRepository,
  ) {}

  onApplicationBootstrap(): void {
    this.revalidateTimer = setInterval(() => {
      void this.expireRevokedSockets();
    }, REVALIDATE_INTERVAL_MS);
    this.revalidateTimer.unref();
  }

  onModuleDestroy(): void {
    if (this.revalidateTimer) clearInterval(this.revalidateTimer);
  }

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
      this.connected.add(client);
      client.emit('ready', { userId: user.id });
    } catch {
      client.emit('auth.error', { code: 'INVALID_ACCESS_TOKEN' });
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    this.connected.delete(client);
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

  /**
   * Routes one domain event to the sockets entitled to see it.
   *
   * Every socket joins `feed` on connect, so anything emitted there reaches
   * every signed-in user. `submission.*`, `social.*` and `profile.updated`
   * were all emitted there with their full payload, which meant a brand-new
   * account with no relationships received strangers' moderation transitions
   * and `profile.updated {"reason":"xp_restored"}`.
   *
   * Only two client surfaces genuinely need a broad signal, and neither reads
   * the payload for anything but a profile id: the leaderboard refreshes on
   * any `profile.updated` / `social.follow.changed` and discards the body
   * entirely, and an open profile page matches on `data.profileId`. So `feed`
   * now carries a trimmed projection of just those two types, and everything
   * else goes to the participants, the post's subscribers, and admins.
   *
   * Nothing consumed `submission.*` from `feed` — the feed list does not
   * subscribe to realtime at all, and every other consumer reads it from
   * `post:{id}`, `user:{id}` or `admin`.
   */
  broadcast(event: RealtimeDomainEvent): void {
    const submissionId = stringValue(event.data.submissionId);
    const userId = stringValue(event.data.userId);
    const targetUserId = stringValue(event.data.targetUserId);
    const profileId = stringValue(event.data.profileId);

    if (event.type === 'admin.user_status_changed') {
      // The one status transition that announces itself, so it need not wait
      // for the next sweep. The admin panel's own suspend/ban bumps
      // `token_version` without emitting anything, and is caught by the timer.
      if (userId) void this.expireRevokedSockets([userId]);
      this.server.to('admin').emit('domain.event', event);
      return;
    }
    if (event.type.startsWith('notification.') && userId) {
      this.server.to(`user:${userId}`).emit('domain.event', event);
      return;
    }
    if (event.type.startsWith('quest.') && userId) {
      this.server.to(`user:${userId}`).emit('domain.event', event);
      return;
    }
    if (event.type.startsWith('submission.')) {
      // Moderation state is between the author, whoever has that post open,
      // and staff. It is not a public signal.
      if (submissionId)
        this.server.to(`post:${submissionId}`).emit('domain.event', event);
      if (userId) this.server.to(`user:${userId}`).emit('domain.event', event);
      this.server.to('admin').emit('domain.event', event);
      return;
    }
    if (event.type === 'social.follow.changed') {
      const participants = [userId, targetUserId].filter(isPresent);
      for (const participant of participants) {
        this.server.to(`user:${participant}`).emit('domain.event', event);
      }
      // Type only: the leaderboard needs to know something moved, not who
      // followed whom.
      this.server
        .to('feed')
        .except(participants.map((id) => `user:${id}`))
        .emit('domain.event', publicProjection(event, {}));
      return;
    }
    if (event.type.startsWith('social.')) {
      if (submissionId)
        this.server.to(`post:${submissionId}`).emit('domain.event', event);
      if (userId) this.server.to(`user:${userId}`).emit('domain.event', event);
      if (targetUserId)
        this.server.to(`user:${targetUserId}`).emit('domain.event', event);
      return;
    }
    if (event.type.startsWith('report.')) {
      this.server.to('admin').emit('domain.event', event);
      return;
    }
    if (event.type === 'profile.updated' && profileId) {
      this.server.to(`user:${profileId}`).emit('domain.event', event);
      // The profile id alone. `reason` and anything else added later stays
      // with the account it belongs to.
      this.server
        .to('feed')
        .except(`user:${profileId}`)
        .emit('domain.event', publicProjection(event, { profileId }));
      return;
    }
    if (event.type.startsWith('admin.')) {
      this.server.to('admin').emit('domain.event', event);
    }
  }

  /**
   * Drops sockets whose session no longer exists.
   *
   * Called on a timer over everything connected, and immediately for one user
   * when an admin changes their status.
   */
  private async expireRevokedSockets(onlyUserIds?: readonly string[]): Promise<void> {
    const scope = onlyUserIds ? new Set(onlyUserIds) : undefined;
    const sockets = [...this.connected].filter((socket) => {
      const user = (socket.data as AuthenticatedSocketData).user;
      return user ? !scope || scope.has(user.id) : false;
    });
    if (sockets.length === 0) return;

    const ids = [
      ...new Set(
        sockets.map(
          (socket) => (socket.data as AuthenticatedSocketData).user!.id,
        ),
      ),
    ];
    let live: Map<string, number>;
    try {
      live = await this.auth.liveTokenVersions(ids);
    } catch (error) {
      // A failed lookup must not disconnect anyone: an unreachable database
      // is not evidence that a session was revoked.
      this.logger.warn(error, 'Session revalidation lookup failed');
      return;
    }

    let dropped = 0;
    for (const socket of sockets) {
      const user = (socket.data as AuthenticatedSocketData).user!;
      const current = live.get(user.id);
      if (current === user.tokenVersion) continue;
      socket.emit('auth.error', { code: 'SESSION_REVOKED' });
      socket.disconnect(true);
      this.connected.delete(socket);
      dropped += 1;
    }
    if (dropped > 0) {
      this.logger.log(`Closed ${dropped} socket(s) on revoked sessions`);
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

/**
 * The same event with its payload narrowed to what a stranger may see.
 *
 * Whitelisted, not blacklisted: a field added to an event later is private
 * until someone decides otherwise here.
 */
function publicProjection(
  event: RealtimeDomainEvent,
  data: Record<string, unknown>,
): RealtimeDomainEvent {
  return { ...event, data };
}

function isPresent(value: string | undefined): value is string {
  return typeof value === 'string' && value.length > 0;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
}
