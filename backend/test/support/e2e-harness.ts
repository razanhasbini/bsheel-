import { INestApplication, ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test, type TestingModule } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../../src/app.module.js';
import { DatabaseService } from '../../src/infrastructure/database/database.service.js';
import type { Environment } from '../../src/config/environment.js';

export interface TestUser {
  readonly id: string;
  readonly email: string;
  readonly username: string;
  readonly displayName: string;
  readonly accessToken: string;
}

export interface TestQuest {
  readonly id: string;
  readonly title: string;
  readonly xp_reward: number;
  readonly duration_hours: number;
}

export interface TestSubmission {
  readonly id: string;
  readonly user_quest_id: string;
  readonly media_url: string;
  readonly caption: string | null;
}

type HttpMethod = 'get' | 'post' | 'patch' | 'put' | 'delete';

/// The password every fixture account uses. It has to satisfy
/// assertPasswordPolicy (length, mixed case, a digit) and must not contain
/// the generated username, which is why it is a fixed unrelated phrase.
const fixturePassword = 'Zephyr-Quartz-9x';

/// Boots the real AppModule once per spec file and owns every row the file
/// creates, so a suite can seed through HTTP and still guarantee the
/// database is back to its starting state afterwards.
///
/// Every fixture identifier carries a per-process random suffix: spec files
/// run in parallel against the same database, so a shared timestamp alone
/// would collide on the citext unique indexes for email and username.
export class E2eHarness {
  private readonly userIds: string[] = [];
  private readonly questIds: string[] = [];
  private readonly trackedIds: string[] = [];
  private counter = 0;
  private readonly runId = `${Date.now().toString(36)}${randomUUID().replaceAll('-', '').slice(0, 6)}`;

  private constructor(
    readonly app: INestApplication,
    readonly prefix: string,
    readonly database: DatabaseService,
  ) {}

  /**
   * @param options.overrides Providers to swap out in this file's app only.
   *   The escape hatch for process-wide state: spec files run in parallel
   *   against one database, so a suite that needs to flip a global switch has
   *   to flip a copy of it or it breaks every other suite mid-run.
   */
  static async boot(
    options: {
      overrides?: readonly { provide: unknown; useValue: unknown }[];
    } = {},
  ): Promise<E2eHarness> {
    let builder = Test.createTestingModule({ imports: [AppModule] });
    for (const override of options.overrides ?? []) {
      builder = builder.overrideProvider(override.provide).useValue(override.useValue);
    }
    const moduleFixture: TestingModule = await builder.compile();

    const app = moduleFixture.createNestApplication();

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
    // Listening once, rather than letting supertest bind a fresh ephemeral
    // port per request.
    //
    // `request(app.getHttpServer())` binds and releases a port for every call
    // when the server is not already listening. Across a full suite that is
    // thousands of bind/close cycles per worker, and under load a few of them
    // produced a response that never reached Nest at all: no entry in the
    // request log, and an Express-level 404 or a reset instead of the
    // handler's answer. It surfaced as a different failing test each run,
    // always inside whichever suite was busiest — which read as flakiness
    // rather than as the harness. Binding once removes the churn: supertest
    // reuses the address of an already-listening server.
    await app.listen(0);

    return new E2eHarness(
      app,
      `/${config.get('API_PREFIX', { infer: true })}/v1`,
      app.get(DatabaseService),
    );
  }

  // --- HTTP -----------------------------------------------------------------

  call(method: HttpMethod, path: string, user?: TestUser) {
    const test = request(this.app.getHttpServer())[method](`${this.prefix}${path}`);
    return user ? test.set('Authorization', `Bearer ${user.accessToken}`) : test;
  }

  /// True only when a response cannot have come from a controller.
  ///
  /// Every response this API produces carries the `{ success, ... }` envelope
  /// that ApiResponseInterceptor and ApiExceptionFilter add, so a >= 400 with
  /// no `success` field was written before Nest ever saw the request — an
  /// Express-level `400 Bad Request` with an HTML body, which is also why
  /// such a response is missing from the nestjs-pino request log (that
  /// middleware runs after the Express body parsers).
  private static neverReachedTheApplication(response: request.Response): boolean {
    if (response.status < 400) return false;
    const body: unknown = response.body;
    return typeof body !== 'object' || body === null || !('success' in body);
  }

  /// Sends a fixture request, re-sending it if the response never reached the
  /// application.
  ///
  /// Seven vitest workers each running an app plus argon2 on an eight-core
  /// laptop produced exactly one such response in ~2,400 requests: a
  /// bodyless 400 that took out a fixture's POST /quests/assign and failed an
  /// unrelated assertion three tests later. Re-sending is safe *because* of
  /// the condition — the request body was never parsed, so no handler ran and
  /// no row was written.
  ///
  /// Only the fixture helpers below use this. A response that did reach a
  /// controller is returned untouched, so every deliberate 4xx assertion in
  /// the suite stays single-shot.
  private async fixtureRequest(build: () => request.Test, attempts = 3): Promise<request.Response> {
    let response = await build();
    for (let attempt = 1; attempt < attempts && E2eHarness.neverReachedTheApplication(response); attempt += 1) {
      response = await build();
    }
    return response;
  }

  get(path: string, user?: TestUser) { return this.call('get', path, user); }
  post(path: string, user?: TestUser) { return this.call('post', path, user); }
  patch(path: string, user?: TestUser) { return this.call('patch', path, user); }
  put(path: string, user?: TestUser) { return this.call('put', path, user); }
  delete(path: string, user?: TestUser) { return this.call('delete', path, user); }

  // --- fixtures -------------------------------------------------------------

  uniqueName(prefix = 'u'): string {
    this.counter += 1;
    return `e2e${prefix}${this.runId}${this.counter}`.slice(0, 30);
  }

  /// Registers through the API, confirms the address directly (the
  /// confirmation email is an out-of-process side effect), then logs in for a
  /// real access token. Roles are granted by inserting into `admins`: the
  /// access-token strategy re-reads the role on every request, so the token
  /// issued before the insert is already an admin token.
  async createUser(options: { role?: 'moderator' | 'super_admin'; prefix?: string } = {}): Promise<TestUser> {
    const username = this.uniqueName(options.prefix);
    const email = `${username}@example.test`;
    const displayName = `Fixture ${username}`;

    const registration = await this.fixtureRequest(() =>
      this.post('/auth/register').send({
        email,
        password: fixturePassword,
        username,
        displayName,
        ageVerified: true,
      }),
    );
    if (registration.status !== 201 && registration.status !== 200) {
      throw new Error(`fixture registration failed: ${registration.status} ${JSON.stringify(registration.body)}`);
    }

    const confirmed = await this.database.query<{ id: string }>(
      `UPDATE users SET email_verified_at = COALESCE(email_verified_at, now())
       WHERE email = $1 RETURNING id`,
      [email],
    );
    const id = confirmed.rows[0].id;
    this.userIds.push(id);
    this.trackedIds.push(id);

    if (options.role) {
      await this.database.query(
        `INSERT INTO admins (user_id, role) VALUES ($1, $2::admin_role)
         ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role`,
        [id, options.role],
      );
    }

    const login = await this.fixtureRequest(() =>
      this.post('/auth/login').send({ email, password: fixturePassword }),
    );
    if (login.status !== 200) {
      throw new Error(`fixture login failed: ${login.status} ${JSON.stringify(login.body)}`);
    }

    return { id, email, username, displayName, accessToken: login.body.data.accessToken };
  }

  /// Quests are inserted directly: creating them through the admin API would
  /// need a super_admin for every suite and would leave `created_by` set,
  /// which changes how the quest picker ranks them.
  async createQuest(options: {
    xpReward?: number;
    durationHours?: number;
    title?: string;
    isActive?: boolean;
    /// A member of the closed set `quests_category_check` allows (migration
    /// 0027). This used to be the hard-coded string 'e2e', which is what put
    /// eight fixture rows outside the legal set in the shared development
    /// database. A test that wants to prove the constraint bites passes an
    /// illegal value here and expects the insert to throw.
    ///
    /// Note for #47: 'e2e' also used to matter because it matched no row in
    /// `quest_verification_defaults`, so a fixture quest resolved to the
    /// fail-closed contract and no test could accidentally hand the
    /// verification agent authority. Every one of the five legal categories
    /// IS seeded, so that trick is no longer available — the fail-closed
    /// default is now written per quest instead, see `verificationAuthority`.
    category?: string;
    /// Whether a fixture quest may be auto-decided by the verification agent
    /// (#47). Defaults to `false`, written as a per-quest override on
    /// `quests.may_auto_approve` / `may_auto_reject`, which
    /// `quest_verification_contract` resolves above the category default.
    /// Pass 'inherit' to fall through to the seeded category default.
    verificationAuthority?: 'fail_closed' | 'inherit';
    /// #51 quest-type columns. Null windows mean "always available", which
    /// is what every pre-existing quest has.
    isHidden?: boolean;
    availableFrom?: Date | null;
    availableUntil?: Date | null;
    sponsorName?: string | null;
  } = {}): Promise<TestQuest> {
    const result = await this.database.query<TestQuest>(
      `INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active,
                           is_hidden, available_from, available_until, sponsor_name,
                           may_auto_approve, may_auto_reject)
       VALUES ($1, $2, $10, 'easy', $3, $4, $5, $6, $7, $8, $9, $11, $11)
       RETURNING id, title, xp_reward, duration_hours`,
      [
        options.title ?? `Quest ${this.uniqueName('q')}`,
        'Fixture quest created by the e2e harness',
        options.xpReward ?? 250,
        options.durationHours ?? 4,
        options.isActive ?? true,
        options.isHidden ?? false,
        options.availableFrom ?? null,
        options.availableUntil ?? null,
        options.sponsorName ?? null,
        options.category ?? 'learning',
        // Fail closed unless a test opts in. Every legal category is seeded
        // in `quest_verification_defaults`, so without this override a
        // fixture quest would inherit auto-approve authority — 'learning'
        // resolves to `provenance_only` with `may_auto_approve = true`. Null
        // inherits the category default, which is what 'inherit' asks for.
        options.verificationAuthority === 'inherit' ? null : false,
      ],
    );
    this.questIds.push(result.rows[0].id);
    this.trackedIds.push(result.rows[0].id);
    return result.rows[0];
  }

  /// Builds a chain over the given quests, in order. Returns the chain id.
  /// Steps are 1-based, matching quest_chain_steps.step_order.
  async createQuestChain(questIds: readonly string[], mode: 'solo' | 'group' = 'solo'): Promise<string> {
    const chain = await this.database.query<{ id: string }>(
      `INSERT INTO quest_chains (name, mode) VALUES ($1, $2) RETURNING id`,
      [`Chain ${this.uniqueName('c')}`, mode],
    );
    const chainId = chain.rows[0].id;
    for (const [index, questId] of questIds.entries()) {
      await this.database.query(
        `INSERT INTO quest_chain_steps (chain_id, quest_id, step_order) VALUES ($1, $2, $3)`,
        [chainId, questId, index + 1],
      );
    }
    return chainId;
  }

  /// Groups quests into a collection and returns its id.
  async createQuestCollection(questIds: readonly string[]): Promise<string> {
    const collection = await this.database.query<{ id: string }>(
      `INSERT INTO quest_collections (name, is_published) VALUES ($1, true) RETURNING id`,
      [`Collection ${this.uniqueName('col')}`],
    );
    const id = collection.rows[0].id;
    for (const questId of questIds) {
      await this.database.query(
        `INSERT INTO quest_collection_items (collection_id, quest_id) VALUES ($1, $2)`,
        [id, questId],
      );
    }
    return id;
  }

  /// Assigns a quest and, by default, ages it past the assignment cooldown.
  ///
  /// Pass `keepCooldown: true` to leave `assigned_at` at now — the suite that
  /// tests the cooldown itself needs a fresh assignment to be refused, which
  /// the default aging would prevent.
  async assignQuest(
    user: TestUser,
    questId: string,
    options: { keepCooldown?: boolean } = {},
  ): Promise<{ id: string }> {
    const response = await this.fixtureRequest(() =>
      this.post('/quests/assign', user).send({ questId }),
    );
    if (response.status !== 201 && response.status !== 200) {
      throw new Error(`fixture assign failed: ${response.status} ${JSON.stringify(response.body)}`);
    }
    this.trackedIds.push(response.body.data.id);
    if (!options.keepCooldown) {
      await this.stepPastAssignmentCooldown(response.body.data.id as string);
    }
    return response.body.data;
  }

  /// A submission only accepts media the caller owns and that the upload
  /// pipeline already marked ready, so the harness fabricates that row
  /// instead of running an R2 upload.
  async createMediaObject(user: TestUser): Promise<string> {
    const objectKey = `submissions/${randomUUID()}/${this.uniqueName('m')}.jpg`;
    await this.database.query(
      `INSERT INTO media_objects
         (user_id, client_request_id, object_key, kind, status, content_type, declared_size_bytes, completed_at)
       VALUES ($1, $2, $3, 'submission', 'ready', 'image/jpeg', 1024, now())`,
      [user.id, randomUUID(), objectKey],
    );
    return objectKey;
  }


  /// Backdates one assignment past the quest-assignment cooldown.
  ///
  /// A player may not take a new quest within
  /// QUEST_ASSIGNMENT_COOLDOWN_SECONDS (30 by default) of their last, keyed
  /// on `assigned_at`. That is correct for players and impossible for
  /// fixtures: several suites give one user three quests inside the same
  /// second, and sleeping 30 seconds per assignment would make the e2e run
  /// unusable.
  ///
  /// The cooldown is deliberately left ENABLED rather than switched off for
  /// the test runner. Turning it off would stop its own suite from
  /// exercising it, and a limit that is disabled wherever it is inconvenient
  /// is a limit nobody is testing. So fixtures age past it instead — exactly
  /// what quest-assignment.e2e-spec.ts already does by hand to reach the
  /// other side of the window.
  ///
  /// 31 seconds keeps every assignment on the same UTC day, so nothing keyed
  /// on the assignment date changes: the Quest-of-the-Day bonus, streak days,
  /// and the EXIF capture window all still see what they expect.
  private async stepPastAssignmentCooldown(userQuestId: string): Promise<void> {
    await this.database.query(
      `UPDATE user_quests SET assigned_at = assigned_at - interval '31 seconds' WHERE id = $1`,
      [userQuestId],
    );
  }

  async createSubmission(
    user: TestUser,
    options: {
      questId?: string;
      caption?: string;
      showInFeed?: boolean;
      mediaUrl?: string;
      /// Leaves `assigned_at` at now, so a following assignment for the same
      /// user is refused by the cooldown. Only the cooldown's own suite wants
      /// this.
      keepCooldown?: boolean;
    } = {},
  ): Promise<TestSubmission> {
    const questId = options.questId ?? (await this.createQuest()).id;
    const assignment = await this.assignQuest(user, questId, {
      keepCooldown: options.keepCooldown,
    });
    const mediaUrl = options.mediaUrl ?? (await this.createMediaObject(user));
    const response = await this.fixtureRequest(() =>
      this.post('/submissions', user).send({
        userQuestId: assignment.id,
        mediaUrl,
        mediaType: 'image',
        ...(options.caption === undefined ? {} : { caption: options.caption }),
        showInFeed: options.showInFeed ?? true,
      }),
    );
    if (response.status !== 201 && response.status !== 200) {
      throw new Error(`fixture submission failed: ${response.status} ${JSON.stringify(response.body)}`);
    }
    this.trackedIds.push(response.body.data.id);
    return response.body.data;
  }

  async activeUserQuestId(user: TestUser): Promise<string> {
    const result = await this.database.query<{ id: string }>(
      `SELECT id FROM user_quests WHERE user_id = $1 AND status IN ('assigned', 'submitted')
       ORDER BY assigned_at DESC LIMIT 1`,
      [user.id],
    );
    if (!result.rows[0]) throw new Error('fixture has no active user_quest');
    return result.rows[0].id;
  }

  /// Creates an approved, feed-visible post in one step: the common shape a
  /// feed, reaction or comment assertion needs.
  async createApprovedPost(
    author: TestUser,
    admin: TestUser,
    options: { caption?: string; questId?: string } = {},
  ): Promise<TestSubmission> {
    const submission = await this.createSubmission(author, options);
    const approval = await this.fixtureRequest(() =>
      this.post(`/submissions/${submission.id}/approve`, admin).send({}),
    );
    if (approval.status !== 204) {
      throw new Error(`fixture approval failed: ${approval.status} ${JSON.stringify(approval.body)}`);
    }
    return submission;
  }

  // --- database reads -------------------------------------------------------

  async profile(userId: string) {
    const result = await this.database.query<{ xp: number; level: number; quests_completed: number; username: string }>(
      'SELECT xp, level, quests_completed, username::text FROM profiles WHERE id = $1',
      [userId],
    );
    return result.rows[0];
  }

  async submission(id: string) {
    const result = await this.database.query<{
      status: string;
      visibility: string;
      appealed: boolean;
      xp_awarded: boolean;
      xp_awarded_amount: number;
      deleted_at: Date | null;
      show_in_feed: boolean;
      appeal_note: string | null;
    }>(
      `SELECT status::text, visibility::text, appealed, xp_awarded, xp_awarded_amount,
              deleted_at, show_in_feed, appeal_note
       FROM submissions WHERE id = $1`,
      [id],
    );
    return result.rows[0];
  }

  async userQuestStatus(id: string): Promise<string | undefined> {
    const result = await this.database.query<{ status: string }>(
      'SELECT status::text FROM user_quests WHERE id = $1',
      [id],
    );
    return result.rows[0]?.status;
  }

  async outboxEvents(aggregateId: string, eventType?: string) {
    const result = await this.database.query<{ event_type: string; payload: Record<string, unknown> }>(
      `SELECT event_type, payload FROM outbox_events
       WHERE aggregate_id = $1 AND ($2::text IS NULL OR event_type = $2)
       ORDER BY occurred_at, id`,
      [aggregateId, eventType ?? null],
    );
    return result.rows;
  }

  /// Moves a submission's `submitted_at` back by whole days so streak runs
  /// can be built without waiting for real ones. Streaks are counted by the
  /// day the work was submitted, so this is the only field that matters.
  async backdateSubmission(id: string, days: number): Promise<void> {
    await this.database.query(
      `UPDATE submissions SET submitted_at = submitted_at - ($2 || ' days')::interval WHERE id = $1`,
      [id, days],
    );
  }

  /// Reads the reminder-idempotency date straight from the profile, so a test
  /// can assert the daily job fires at most once per user per day.
  async streakReminderSentOn(userId: string): Promise<string | null> {
    const result = await this.database.query<{ sent: string | null }>(
      `SELECT to_char(streak_reminder_sent_on, 'YYYY-MM-DD') AS sent FROM profiles WHERE id = $1`,
      [userId],
    );
    return result.rows[0]?.sent ?? null;
  }

  async notificationsFor(userId: string, referenceId?: string) {
    const result = await this.database.query<{ id: string; type: string; user_id: string; actor_id: string | null; title: string }>(
      `SELECT id, type, user_id, actor_id, title FROM notifications
       WHERE user_id = $1 AND ($2::uuid IS NULL OR reference_id = $2)
       ORDER BY created_at, id`,
      [userId, referenceId ?? null],
    );
    return result.rows;
  }

  async auditRows(action: string, targetId: string) {
    const result = await this.database.query<{
      actor_id: string | null;
      action: string;
      before_state: Record<string, unknown> | null;
      after_state: Record<string, unknown> | null;
    }>(
      `SELECT actor_id, action, before_state, after_state FROM admin_audit_log
       WHERE action = $1 AND target_id = $2 ORDER BY created_at, id`,
      [action, targetId],
    );
    return result.rows;
  }

  async countRows(sql: string, values: readonly unknown[]): Promise<number> {
    const result = await this.database.query<{ count: string }>(sql, values);
    return Number(result.rows[0].count);
  }

  track(...ids: readonly string[]): void {
    this.trackedIds.push(...ids);
  }

  /// Registers a quest the suite created through the API, so teardown removes
  /// the row. createQuest() does this for itself.
  trackQuest(...ids: readonly string[]): void {
    this.questIds.push(...ids);
    this.trackedIds.push(...ids);
  }

  // --- teardown -------------------------------------------------------------

  async close(): Promise<void> {
    try {
      if (this.userIds.length) {
        // Revoke the admin grants first, in their own committed statement.
        // POST /submissions notifies every row in `admins`
        // (INSERT ... SELECT user_id FROM admins), so a spec file running in
        // parallel can be inside that insert while this one tears down. If
        // the admins row and the users row disappeared in one transaction,
        // that in-flight insert fails the notifications -> users foreign key
        // and the submission 500s. Dropping the grant first, then pausing so
        // any statement that already read the row commits, keeps the key
        // satisfiable.
        await this.database.query('DELETE FROM admins WHERE user_id = ANY($1::uuid[])', [this.userIds]);
        await new Promise((resolve) => setTimeout(resolve, 750));
      }

      if (this.trackedIds.length || this.userIds.length) {
        // outbox_events and admin_audit_log carry no foreign key back to the
        // aggregate, so cascading a user delete would leave them behind. The
        // dependent ids have to be collected before the users go.
        await this.database.query(
          `DELETE FROM outbox_events
           WHERE aggregate_id IN (
                   SELECT unnest($1::uuid[])
                   UNION ALL SELECT unnest($2::uuid[])
                   UNION ALL SELECT id FROM submissions WHERE user_id = ANY($2::uuid[])
                   UNION ALL SELECT id FROM user_quests WHERE user_id = ANY($2::uuid[])
                   UNION ALL SELECT id FROM notifications WHERE user_id = ANY($2::uuid[])
                   UNION ALL SELECT id FROM comments WHERE user_id = ANY($2::uuid[])
                   UNION ALL SELECT id FROM reports WHERE reporter_id = ANY($2::uuid[])
                   UNION ALL SELECT id FROM auth_action_tokens WHERE user_id = ANY($2::uuid[])
                   UNION ALL SELECT id FROM follows
                     WHERE follower_id = ANY($2::uuid[]) OR following_id = ANY($2::uuid[])
                 )
              OR payload->>'userId' = ANY($3::text[])
              OR payload->>'submissionId' = ANY($3::text[])
              OR payload->>'profileId' = ANY($3::text[])
              OR payload->>'targetUserId' = ANY($3::text[])`,
          [this.trackedIds, this.userIds, this.trackedIds],
        );
        // admin_audit_log is deliberately NOT cleaned up. Migration 0027 made
        // it append-only in the database, so the DELETE that used to sit here
        // now raises restrict_violation — which is the guarantee working, not
        // a bug to route around. Fixture audit rows therefore accumulate in a
        // development database; they are inert (no foreign key points at them
        // and every assertion here selects by a per-run target_id), and the
        // owner-only ALTER TABLE ... DISABLE TRIGGER escape hatch exists if a
        // developer ever wants the table empty again.
      }

      if (this.userIds.length) {
        // Profiles, identities, submissions, notifications and the whole
        // social graph cascade from users.
        await this.database.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [this.userIds]);
      }
      if (this.questIds.length) {
        await this.database.query('DELETE FROM quests WHERE id = ANY($1::uuid[])', [this.questIds]);
      }
    } finally {
      await this.app.close();
    }
  }
}
