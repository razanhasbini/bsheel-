import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection } from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import type { Environment } from '../../config/environment.js';
import { AuthRepository } from '../../modules/auth/infrastructure/auth.repository.js';
import type { RealtimeDomainEvent } from './realtime-event.publisher.js';
export declare class RealtimeGateway implements OnGatewayConnection {
    private readonly jwt;
    private readonly config;
    private readonly auth;
    private readonly logger;
    server: Server;
    constructor(jwt: JwtService, config: ConfigService<Environment, true>, auth: AuthRepository);
    handleConnection(client: Socket): Promise<void>;
    subscribePost(client: Socket, body: {
        submissionId?: unknown;
    }): Promise<{
        ok: true;
    } | {
        ok: false;
        code: string;
    }>;
    unsubscribePost(client: Socket, body: {
        submissionId?: unknown;
    }): Promise<{
        ok: true;
    } | {
        ok: false;
        code: string;
    }>;
    broadcast(event: RealtimeDomainEvent): void;
    private connectionToken;
}
