import { OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { type PoolClient, type QueryResult, type QueryResultRow } from 'pg';
import type { Environment } from '../../config/environment.js';
export type DatabaseTransaction = PoolClient;
export declare class DatabaseService implements OnModuleDestroy {
    private readonly logger;
    private readonly pool;
    constructor(config: ConfigService<Environment, true>);
    query<Row extends QueryResultRow = QueryResultRow>(text: string, values?: readonly unknown[], transaction?: DatabaseTransaction): Promise<QueryResult<Row>>;
    transaction<T>(work: (transaction: DatabaseTransaction) => Promise<T>): Promise<T>;
    ping(): Promise<void>;
    onModuleDestroy(): Promise<void>;
}
