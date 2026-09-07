import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
export declare class DeviceTokenCipher {
    private readonly key;
    constructor(config: ConfigService<Environment, true>);
    protect(token: string): {
        hash: Buffer;
        encrypted: Buffer;
    };
    unprotect(encrypted: Buffer): string;
}
