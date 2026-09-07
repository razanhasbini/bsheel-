import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
export interface PushDeliveryResult {
    readonly invalidToken: boolean;
    readonly messageName?: string;
}
export declare class FirebasePushService {
    private readonly config;
    private readonly enabled;
    private readonly account?;
    private readonly projectId;
    private readonly timeoutMs;
    private accessToken?;
    private accessTokenExpiresAt;
    private accessTokenRequest?;
    constructor(config: ConfigService<Environment, true>);
    send(token: string, title: string, body: string): Promise<PushDeliveryResult>;
    private sendWithAuthentication;
    private getAccessToken;
    private requestAccessToken;
    private parseAccount;
    private readJson;
    private isInvalidToken;
}
