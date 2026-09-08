import { INestApplication, ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module.js';
import type { Environment } from '../src/config/environment.js';

// Boots the real AppModule against the configured PostgreSQL and Redis and
// asserts the platform contract the applications depend on: the versioned
// prefix, the success/error envelope, authentication separate from
// authorization, and global DTO validation.
//
// Requires DATABASE_URL and REDIS_URL to point at disposable services.
describe('platform contract (e2e)', () => {
  let app: INestApplication;
  let prefix: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();

    // Mirror src/main.ts so the suite exercises the shipped configuration
    // rather than a bare Nest app.
    const config = app.get(ConfigService<Environment, true>);
    app.setGlobalPrefix(config.get('API_PREFIX', { infer: true }));
    app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });
    app.useGlobalPipes(
      new ValidationPipe({
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
        stopAtFirstError: false,
      }),
    );
    prefix = `/${config.get('API_PREFIX', { infer: true })}/v1`;

    await app.init();
  }, 60_000);

  afterAll(async () => {
    await app?.close();
  });

  describe('versioned prefix', () => {
    it('serves liveness under the versioned prefix', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/health/live`)
        .expect(200);

      expect(response.body).toMatchObject({
        success: true,
        data: { status: 'ok' },
      });
    });

    it('does not serve the same route without the prefix', async () => {
      await request(app.getHttpServer()).get('/health/live').expect(404);
    });
  });

  describe('response envelope', () => {
    it('wraps a success payload with request id and timestamp', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/health/live`)
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(typeof response.body.meta.requestId).toBe('string');
      expect(response.body.meta.requestId.length).toBeGreaterThan(0);
      expect(Number.isNaN(Date.parse(response.body.meta.timestamp))).toBe(false);
    });

    it('echoes a supplied request id so a client can correlate a failure', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/health/live`)
        .set('x-request-id', 'e2e-correlation-id')
        .expect(200);

      expect(response.headers['x-request-id']).toBe('e2e-correlation-id');
      expect(response.body.meta.requestId).toBe('e2e-correlation-id');
    });

    it('wraps an unknown route in the error envelope', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/definitely-not-a-route`)
        .expect(404);

      expect(response.body.success).toBe(false);
      expect(typeof response.body.error.code).toBe('string');
      expect(typeof response.body.error.message).toBe('string');
      expect(typeof response.body.meta.requestId).toBe('string');
    });
  });

  describe('authentication', () => {
    it('rejects an authenticated route with no bearer token', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/profiles/me`)
        .expect(401);

      expect(response.body.success).toBe(false);
    });

    it('rejects a malformed bearer token', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/profiles/me`)
        .set('Authorization', 'Bearer not-a-real-token')
        .expect(401);

      expect(response.body.success).toBe(false);
    });

    it('leaves a public route reachable without a token', async () => {
      await request(app.getHttpServer()).get(`${prefix}/config`).expect(200);
    });
  });

  describe('global DTO validation', () => {
    it('rejects a missing required field', async () => {
      const response = await request(app.getHttpServer())
        .post(`${prefix}/auth/login`)
        .send({})
        .expect(400);

      expect(response.body.success).toBe(false);
    });

    it('rejects an unknown field rather than silently ignoring it', async () => {
      const response = await request(app.getHttpServer())
        .post(`${prefix}/auth/login`)
        .send({
          email: 'nobody@example.test',
          password: 'Sufficiently-Long-1',
          isAdmin: true,
        })
        .expect(400);

      expect(response.body.success).toBe(false);
      expect(JSON.stringify(response.body.error)).toMatch(/isAdmin/);
    });

    it('rejects a malformed email before touching the database', async () => {
      await request(app.getHttpServer())
        .post(`${prefix}/auth/login`)
        .send({ email: 'not-an-email', password: 'Sufficiently-Long-1' })
        .expect(400);
    });
  });

  describe('dependency readiness', () => {
    it('reports PostgreSQL and Redis up against the real services', async () => {
      const response = await request(app.getHttpServer())
        .get(`${prefix}/health/ready`)
        .expect(200);

      expect(response.body.data).toMatchObject({
        status: 'ok',
        dependencies: { postgres: 'up', redis: 'up' },
      });
    });
  });
});
