import type { AuthUser } from '../../../common/auth/auth-user.js';
import { AccountService } from '../application/account.service.js';
import { RequestDeletionDto } from './account.dto.js';
export declare class AccountController {
    private readonly service;
    constructor(service: AccountService);
    requestExport(user: AuthUser): Promise<{
        id: string;
        status: string;
        requestedAt: Date;
    }>;
    exports(user: AuthUser): Promise<{
        download_url: string | null;
    }[]>;
    requestDeletion(user: AuthUser, _body: RequestDeletionDto): Promise<{
        requestId: string;
        executeAfter: Date;
    }>;
}
