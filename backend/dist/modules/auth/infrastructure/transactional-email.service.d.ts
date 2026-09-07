import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
export declare class TransactionalEmailService {
    private readonly endpoint?;
    private readonly secret?;
    private readonly publicUrl;
    private readonly timeoutMs;
    constructor(config: ConfigService<Environment, true>);
    sendPasswordRecovery(email: string, token: string): Promise<void>;
    sendEmailConfirmation(email: string, token: string): Promise<void>;
    private sendActionEmail;
}
