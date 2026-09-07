import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
export interface OAuthIdentity {
    readonly provider: 'google' | 'apple';
    readonly subject: string;
    readonly email: string;
    readonly displayName?: string;
}
export declare class OAuthIdentityVerifier {
    private readonly google;
    private readonly googleAudiences;
    private readonly appleAudiences;
    private readonly appleKeys;
    constructor(config: ConfigService<Environment, true>);
    verify(provider: 'google' | 'apple', idToken: string, nonce?: string, displayName?: string): Promise<OAuthIdentity>;
    private verifyGoogle;
    private verifyApple;
    private invalid;
    private notConfigured;
}
