var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var DatabaseService_1;
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';
let DatabaseService = DatabaseService_1 = class DatabaseService {
    logger = new Logger(DatabaseService_1.name);
    pool;
    constructor(config) {
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
    query(text, values = [], transaction) {
        return (transaction ?? this.pool).query(text, [...values]);
    }
    async transaction(work) {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            const result = await work(client);
            await client.query('COMMIT');
            return result;
        }
        catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        finally {
            client.release();
        }
    }
    async ping() {
        await this.pool.query('SELECT 1');
    }
    async onModuleDestroy() {
        await this.pool.end();
    }
};
DatabaseService = DatabaseService_1 = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], DatabaseService);
export { DatabaseService };
//# sourceMappingURL=database.service.js.map