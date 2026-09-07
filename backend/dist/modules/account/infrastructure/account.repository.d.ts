import { DatabaseService } from '../../../infrastructure/database/database.service.js';
export declare class AccountRepository {
    private readonly database;
    constructor(database: DatabaseService);
    requestExport(userId: string): Promise<{
        id: string;
        status: string;
        requestedAt: Date;
    }>;
    exports(userId: string): Promise<import("pg").QueryResultRow[]>;
    requestDeletion(userId: string): Promise<{
        requestId: string;
        executeAfter: Date;
    }>;
}
