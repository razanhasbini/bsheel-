import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// The verification contract, against the real database (#47).
///
/// The unit tests cover `decide()` in isolation. What they cannot cover is
/// whether the *resolved* contract a quest actually gets is the one the
/// policy will be handed — that depends on the view, the seeded category
/// defaults and the override columns agreeing, which is a schema question.
///
/// This is the guard against the failure that motivated the whole contract:
/// an agent being asked whether a photograph proves something no photograph
/// could, and confidently rejecting an honest player for failing an
/// impossible test.
describe('quest verification contract (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;

  const contractFor = async (questId: string) => {
    const result = await harness.database.query<{
      verifiability: string;
      evidence_rubric: string;
      may_auto_approve: boolean;
      may_auto_reject: boolean;
    }>(
      `SELECT verifiability::text, evidence_rubric, may_auto_approve, may_auto_reject
       FROM quest_verification_contract WHERE quest_id = $1`,
      [questId],
    );
    return result.rows[0];
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  });

  afterAll(async () => {
    await harness?.close();
  });

  it('seeds a contract for all five categories', async () => {
    const result = await harness.database.query<{ category: string; verifiability: string }>(
      'SELECT category, verifiability::text FROM quest_verification_defaults ORDER BY category',
    );
    expect(result.rows.map((row) => row.category)).toEqual([
      'adventure', 'creativity', 'fitness', 'learning', 'social',
    ]);
  });

  // The distinction the whole design rests on. `social` quests — "compliment
  // a stranger and mean it" — cannot be checked by photograph, and the
  // contract has to say so rather than leaving a model to guess.
  it('marks social quests unverifiable and learning quests provenance-only', async () => {
    const social = await harness.createQuest({ category: 'social' });
    const learning = await harness.createQuest({ category: 'learning' });
    expect((await contractFor(social.id)).verifiability).toBe('none');
    expect((await contractFor(learning.id)).verifiability).toBe('provenance_only');
  });

  it('marks the checkable categories as content-verifiable', async () => {
    for (const category of ['creativity', 'fitness', 'adventure']) {
      const quest = await harness.createQuest({ category });
      expect((await contractFor(quest.id)).verifiability).toBe('content');
    }
  });

  // Authority is earned by measurement, not asserted in a migration. Until
  // the eval produces a precision number, nothing may reject automatically.
  it('grants no category the power to auto-reject out of the box', async () => {
    const result = await harness.database.query<{ count: string }>(
      'SELECT count(*) FROM quest_verification_defaults WHERE may_auto_reject',
    );
    expect(Number(result.rows[0].count)).toBe(0);
  });

  // A category default cannot be right for every quest in it: "Watch the
  // sunrise" and "Spend an hour with no phone" are both adventure, and only
  // one is checkable. This is the escape hatch for that.
  it('lets a per-quest override beat the category default', async () => {
    const quest = await harness.createQuest({ category: 'adventure' });
    expect((await contractFor(quest.id)).verifiability).toBe('content');

    await harness.database.query(
      `UPDATE quests
       SET verifiability = 'none', evidence_rubric = 'The phone took the photograph.',
           may_auto_approve = true, may_auto_reject = false
       WHERE id = $1`,
      [quest.id],
    );

    const overridden = await contractFor(quest.id);
    expect(overridden.verifiability).toBe('none');
    expect(overridden.evidence_rubric).toBe('The phone took the photograph.');
    expect(overridden.may_auto_reject).toBe(false);
  });

  // An unknown category must fail closed. Getting this wrong the other way
  // would make a typo in a category name the most permissive setting in the
  // system.
  // This used to create a quest in category 'category-that-has-no-default'.
  // Migration 0027 closed `quests.category` to five values, so an unseeded
  // category can no longer exist as data — and all five ARE seeded. The
  // fail-closed branch of the view is therefore unreachable through legal
  // rows, but it is still the property that matters if a default is ever
  // removed, so it is provoked directly instead of through an illegal row.
  it('fails closed when a category has no default', async () => {
    const quest = await harness.createQuest({ category: 'social' });
    await harness.database.query('BEGIN');
    try {
      await harness.database.query(
        "DELETE FROM quest_verification_defaults WHERE category = 'social'",
      );
      const contract = await contractFor(quest.id);
      expect(contract.verifiability).toBe('none');
      expect(contract.may_auto_approve).toBe(false);
      expect(contract.may_auto_reject).toBe(false);
      expect(contract.evidence_rubric).toContain('Escalate to a human');
    } finally {
      await harness.database.query('ROLLBACK');
    }
  });

  it('refuses a quest whose category is outside the closed set', async () => {
    await expect(
      harness.createQuest({ category: 'category-that-has-no-default' }),
    ).rejects.toThrow(/quests_category_check/);
  });

  // The safety property the suite depends on: no fixture quest hands the
  // agent authority. It used to hold because every fixture used category
  // 'e2e', which matched no seeded default. All five legal categories are
  // seeded now, so the harness writes a per-quest override instead —
  // `verifiability` is inherited and describes what CAN be checked, while
  // `may_auto_*` is what the agent MAY act on, and that is what must be off.
  it("gives the harness's own fixture quests no authority", async () => {
    const quest = await harness.createQuest();
    const contract = await contractFor(quest.id);
    expect(contract.may_auto_approve).toBe(false);
    expect(contract.may_auto_reject).toBe(false);
  });

  it('lets a test opt back into the seeded category default', async () => {
    const quest = await harness.createQuest({
      category: 'learning',
      verificationAuthority: 'inherit',
    });
    const contract = await contractFor(quest.id);
    expect(contract.verifiability).toBe('provenance_only');
    expect(contract.may_auto_approve).toBe(true);
  });

  it('gives every quest exactly one resolved contract', async () => {
    const result = await harness.database.query<{ quests: string; contracts: string }>(
      `SELECT (SELECT count(*) FROM quests) AS quests,
              (SELECT count(*) FROM quest_verification_contract) AS contracts`,
    );
    expect(result.rows[0].contracts).toBe(result.rows[0].quests);
  });

  // Every rubric is handed to a model as instructions, so an empty one would
  // silently remove the guardrail for that category.
  it('gives every category a non-trivial rubric', async () => {
    const result = await harness.database.query<{ category: string; length: number }>(
      'SELECT category, char_length(evidence_rubric)::int AS length FROM quest_verification_defaults',
    );
    for (const row of result.rows) {
      expect(row.length, `${row.category} rubric`).toBeGreaterThan(80);
    }
  });
});

/// The forensics columns and near-duplicate search, against real Postgres.
///
/// `bit_count(a # b)` is computed by the database, so the distance the policy
/// sees is Postgres arithmetic rather than the TypeScript implementation the
/// unit tests exercise. If those two ever disagree, duplicate detection is
/// wrong in production and right in CI.
describe('perceptual hash search (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let user: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    user = await harness.createUser({ prefix: 'phash' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  const distance = async (left: string, right: string): Promise<number> => {
    const result = await harness.database.query<{ d: number }>(
      'SELECT bit_count($1::bit(64) # $2::bit(64))::int AS d',
      [left, right],
    );
    return result.rows[0].d;
  };

  it('computes Hamming distance the same way the domain code does', async () => {
    const a = '1'.repeat(64);
    const b = `${'0'.repeat(10)}${'1'.repeat(54)}`;
    expect(await distance(a, a)).toBe(0);
    expect(await distance(a, b)).toBe(10);
  });

  it('stores and returns a 64-bit hash unchanged', async () => {
    const submission = await harness.createSubmission(user, { caption: 'hash round trip' });
    const hash = `${'1010'.repeat(15)}0101`;
    await harness.database.query(
      `INSERT INTO media_objects
         (user_id, client_request_id, object_key, kind, status, content_type,
          declared_size_bytes, upload_expires_at, perceptual_hash, content_md5, submission_id)
       VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', 'image/jpeg', 1024, now(),
               $3::bit(64), $4, $5)`,
      [user.id, `submissions/${user.id}/phash-${Date.now()}.jpg`, hash, 'a'.repeat(32), submission.id],
    );
    const result = await harness.database.query<{ perceptual_hash: string }>(
      'SELECT perceptual_hash::text FROM media_objects WHERE submission_id = $1',
      [submission.id],
    );
    expect(result.rows[0].perceptual_hash).toBe(hash);
  });

  it('rejects a content hash that is not an MD5', async () => {
    await expect(
      harness.database.query(
        `INSERT INTO media_objects
           (user_id, client_request_id, object_key, kind, status, content_type,
            declared_size_bytes, upload_expires_at, content_md5)
         VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', 'image/jpeg', 1024, now(), 'not-a-hash')`,
        [user.id, `submissions/${user.id}/bad-${Date.now()}.jpg`],
      ),
    ).rejects.toThrow();
  });
});
