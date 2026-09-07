import { ObjectStorageService } from '../../media/infrastructure/object-storage.service.js';
import { AccountRepository } from '../infrastructure/account.repository.js';
export declare class AccountService {
    private readonly repository;
    private readonly storage;
    constructor(repository: AccountRepository, storage: ObjectStorageService);
    requestExport(userId: string): Promise<{
        id: string;
        status: string;
        requestedAt: Date;
    }>;
    exports(userId: string): Promise<{
        download_url: string | null;
    }[]>;
    requestDeletion(userId: string): Promise<{
        requestId: string;
        executeAfter: Date;
    }>;
}
