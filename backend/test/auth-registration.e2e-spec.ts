import { INestApplication, ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module.js';
import { DatabaseService } from '../src/infrastructure/database/database.service.js';
import type { Environment } from '../src/config/environment.js';

// Registration conflicts against the real database.
//
// The signup form routes a conflict message to a specific field, so the API
// has to say which value collided. A single ACCOUNT_CONFLICT code cannot be
// mapped to a field and regresses the legacy behavior, where a taken username
// and an already-registered email produced different errors on different
// inputs.
describe('registration conflicts (e2e)', () => {
  let app: INestApplication;
  let database: DatabaseService;
  let prefix: string;

  const unique = Date.now();
  const email = `conflict-${unique}@example.test`;
  const username = `conflict${unique}`.slice(0, 28);
  const password = 'Str0ng-Passphrase-9';

  const register = (body: Record<string, unknown>) =>
    request(app.getHttpServer()).post(`${prefix}/auth/register`).send(body);

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
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

    database = app.get(DatabaseService);

    // Seed the account the conflict cases collide with.
    await register({
      email,
      password,
      username,
      displayName: 'Conflict Fixture',
      ageVerified: true,
    }).expect((response) => {
      if (response.status !== 201 && response.status !== 200) {
        throw new Error(
          `seed registration failed: ${response.status} ${JSON.stringify(response.body)}`,
        );
      }
    });
  }, 60_000);

  afterAll(async () => {
    if (database) {
      for (const address of [email, `other-${email}`]) {
        // outbox_events carries no foreign key back to its aggregate, so the
        // `user.created` row written by a successful registration outlives
        // the cascade and would leave one row behind on every run. It has to
        // be collected while the user still exists.
        const seeded = await database.query<{ id: string }>(
          'SELECT id FROM users WHERE email = $1',
          [address],
        );
        for (const row of seeded.rows) {
          await database.query(
            `DELETE FROM outbox_events
             WHERE aggregate_id = $1::uuid OR payload->>'userId' = $2::text`,
            [row.id, row.id],
          );
        }
        // Profiles and identities cascade from users.
        await database.query('DELETE FROM users WHERE email = $1', [address]);
      }
    }
    await app?.close();
  });

  it('reports EMAIL_TAKEN when only the email collides', async () => {
    const response = await register({
      email,
      password,
      username: `${username}b`.slice(0, 30),
      displayName: 'Other Person',
      ageVerified: true,
    }).expect(409);

    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe('EMAIL_TAKEN');
  });

  it('reports USERNAME_TAKEN when only the username collides', async () => {
    const response = await register({
      email: `other-${email}`,
      password,
      username,
      displayName: 'Other Person',
      ageVerified: true,
    }).expect(409);

    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe('USERNAME_TAKEN');
  });

  it('rejects registration without age confirmation', async () => {
    const response = await register({
      email: `age-${email}`,
      password,
      username: `age${unique}`.slice(0, 30),
      displayName: 'Too Young',
      ageVerified: false,
    }).expect(403);

    expect(response.body.error.code).toBe('AGE_VERIFICATION_REQUIRED');
  });

  it('rejects a password that fails the policy', async () => {
    const response = await register({
      email: `weak-${email}`,
      password: 'short',
      username: `weak${unique}`.slice(0, 30),
      displayName: 'Weak Password',
      ageVerified: true,
    });

    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.body.success).toBe(false);
  });
});
