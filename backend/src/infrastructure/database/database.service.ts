import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, type PoolClient, type QueryResult, type QueryResultRow } from 'pg';
import type { Environment } from '../../config/environment.js';

export type DatabaseTransaction = PoolClient;

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly logger = new Logger(DatabaseService.name);
  private readonly pool: Pool;

  constructor(config: ConfigService<Environment, true>) {
    this.pool = new Pool({
      connectionString: config.get('DATABASE_URL', { infer: true }),
      min: config.get('DATABASE_POOL_MIN', { infer: true }),
      max: config.get('DATABASE_POOL_MAX', { infer: true }),
      idleTimeoutMillis: config.get('DATABASE_IDLE_TIMEOUT_MS', { infer: true }),
      statement_timeout: config.get('DATABASE_STATEMENT_TIMEOUT_MS', { infer: true }),
      application_name: config.get('APP_NAME', { infer: true }),
    });
    this.pool.on('error', (error) => this.logger.error(error, 'Idle database client error'));
  }

  query<Row extends QueryResultRow = QueryResultRow>(
    text: string,
    values: readonly unknown[] = [],
    transaction?: DatabaseTransaction,
  ): Promise<QueryResult<Row>> {
    return (transaction ?? this.pool).query<Row>(text, [...values]);
  }

  async transaction<T>(work: (transaction: DatabaseTransaction) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async ping(): Promise<void> {
    await this.pool.query('SELECT 1');
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}

