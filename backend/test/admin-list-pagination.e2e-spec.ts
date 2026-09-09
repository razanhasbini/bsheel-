import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// Keyset pagination for the admin submission lists (#59).
///
/// Every assertion here walks the whole list and checks the *set* of ids,
/// not a status code. Keyset bugs are silent by nature: a comparison that
/// disagrees with its ORDER BY returns the page you just saw, and a boundary
/// off by one drops a row between pages. Neither errors, and both look
/// exactly like a working paginator until someone notices a submission that
/// no page contains.
describe('admin list keyset pagination (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;
  /// Submissions created by this suite, so assertions can ignore whatever
  /// else the shared database holds.
  const owned = new Set<string>();

  /// Walks a list to exhaustion by cursor, returning ids in page order.
  const walk = async (
    path: string,
    limit: number,
  ): Promise<{ ids: string[]; pages: number }> => {
    const ids: string[] = [];
    let cursor: string | undefined;
    let pages = 0;
    // Bounded so a cursor that fails to advance ends the test rather than
    // hanging the suite — which is itself the bug this guards against.
    while (pages < 60) {
      const query = `${path}${path.includes('?') ? '&' : '?'}limit=${limit}`
        + (cursor ? `&cursor=${encodeURIComponent(cursor)}` : '');
      const response = await harness.get(query, moderator).expect(200);
      const rows: { id: string; next_cursor: string | null }[] = response.body.data;
      pages += 1;
      ids.push(...rows.map((row) => row.id));
      const next = rows.at(-1)?.next_cursor ?? null;
      if (!next) break;
      cursor = next;
    }
    return { ids, pages };
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 'pagemod' });
    // Seven submissions across three users, because the one-assigned-quest
    // index caps how many a single user can have in flight.
    for (let index = 0; index < 3; index += 1) {
      const user = await harness.createUser({ prefix: `pageu${index}` });
      for (let attempt = 0; attempt < 3 && owned.size < 7; attempt += 1) {
        const submission = await harness.createSubmission(user, {
          caption: `pagination fixture ${owned.size}`,
        });
        owned.add(submission.id);
      }
    }
  });

  afterAll(async () => {
    await harness?.close();
  });

  it('creates the fixtures it needs', () => {
    expect(owned.size).toBe(7);
  });

  // The bug that matters: a paginator that returns everything exactly once.
  it('covers every row exactly once across pages, ascending', async () => {
    const { ids, pages } = await walk('/submissions/admin?status=all&order=asc', 3);
    expect(pages).toBeGreaterThan(1);
    expect(new Set(ids).size).toBe(ids.length);
    for (const id of owned) expect(ids).toContain(id);
  });

  // The comparison has to follow the sort. Reversing one without the other
  // is the classic keyset error and it returns the first page forever.
  it('covers every row exactly once across pages, descending', async () => {
    const { ids, pages } = await walk('/submissions/admin?status=all&order=desc', 3);
    expect(pages).toBeGreaterThan(1);
    expect(new Set(ids).size).toBe(ids.length);
    for (const id of owned) expect(ids).toContain(id);
  });

  it('returns the same set of rows by cursor as by offset', async () => {
    const byCursor = await walk('/submissions/admin?status=all&order=asc', 3);
    const byOffset: string[] = [];
    for (let offset = 0; offset < 60; offset += 20) {
      const response = await harness
        .get(`/submissions/admin?status=all&order=asc&limit=20&offset=${offset}`, moderator)
        .expect(200);
      byOffset.push(...response.body.data.map((row: { id: string }) => row.id));
      if (response.body.data.length < 20) break;
    }
    // Compared as sets over the fixtures this suite owns: the shared database
    // is being written by other suites in parallel, so the tails differ.
    const cursorSet = new Set(byCursor.ids);
    const offsetSet = new Set(byOffset);
    for (const id of owned) {
      expect(cursorSet.has(id), `cursor walk missing ${id}`).toBe(true);
      expect(offsetSet.has(id), `offset walk missing ${id}`).toBe(true);
    }
  });

  it('preserves the ordering it claims', async () => {
    const response = await harness
      .get('/submissions/admin?status=all&order=asc&limit=50', moderator)
      .expect(200);
    const times = response.body.data.map((row: { submitted_at: string }) =>
      Date.parse(row.submitted_at));
    expect(times).toEqual([...times].sort((a, b) => a - b));
  });

  // A short page is the end-of-list signal, so it must not offer a cursor
  // that leads nowhere.
  it('stops offering a cursor once the page is short', async () => {
    const response = await harness
      .get('/submissions/admin?status=all&limit=100', moderator)
      .expect(200);
    const rows: { next_cursor: string | null }[] = response.body.data;
    if (rows.length < 100) {
      expect(rows.at(-1)?.next_cursor).toBeNull();
    }
    // Only the last row of a full page carries one; the rest are null, so a
    // client cannot accidentally page from the middle.
    for (const row of rows.slice(0, -1)) expect(row.next_cursor).toBeNull();
  });

  // The context binding is the reason to prefer keyset-cursor.ts over the
  // plainer helper: these are several distinct lists, and a cursor leaking
  // between them would silently page through the wrong ordering.
  it('refuses a cursor issued by a different list', async () => {
    const queue = await harness
      .get('/submissions/admin/review-queue?limit=1', moderator)
      .expect(200);
    const queueCursor = queue.body.data.at(-1)?.next_cursor;
    if (!queueCursor) return;

    const response = await harness
      .get(`/submissions/admin?status=all&limit=5&cursor=${encodeURIComponent(queueCursor)}`, moderator)
      .expect(400);
    expect(response.body.error.code).toBe('INVALID_CURSOR');
  });

  it('refuses a malformed cursor with a stable error code', async () => {
    for (const cursor of ['not-base64!!', Buffer.from('{}').toString('base64url')]) {
      const response = await harness
        .get(`/submissions/admin?status=all&cursor=${encodeURIComponent(cursor)}`, moderator)
        .expect(400);
      expect(response.body.error.code).toBe('INVALID_CURSOR');
    }
  });

  // Rejected by the DTO's length cap before the decoder ever runs, which is
  // the right place for it — a 2 KB query parameter is not a cursor problem.
  it('refuses an oversized cursor at validation', async () => {
    await harness
      .get(`/submissions/admin?status=all&cursor=${'a'.repeat(2000)}`, moderator)
      .expect(400);
  });

  it('paginates the review queue and keeps its computed columns', async () => {
    const { ids, pages } = await walk('/submissions/admin/review-queue', 2);
    expect(pages).toBeGreaterThan(1);
    expect(new Set(ids).size).toBe(ids.length);

    // The queue's enrichment is computed per page, so it has to survive
    // pagination rather than only appearing on page one.
    const response = await harness
      .get('/submissions/admin/review-queue?limit=2', moderator)
      .expect(200);
    for (const row of response.body.data) {
      expect(row).toHaveProperty('user_approved_count');
      expect(row).toHaveProperty('is_duplicate');
    }
  });

  // Combining the two would skip rows: the offset would be applied on top of
  // a window the cursor had already advanced past.
  it('ignores offset when a cursor is supplied', async () => {
    const first = await harness
      .get('/submissions/admin?status=all&order=asc&limit=2', moderator)
      .expect(200);
    const cursor = first.body.data.at(-1)?.next_cursor;
    expect(cursor).toBeTruthy();

    const withoutOffset = await harness
      .get(`/submissions/admin?status=all&order=asc&limit=2&cursor=${encodeURIComponent(cursor)}`, moderator)
      .expect(200);
    const withOffset = await harness
      .get(`/submissions/admin?status=all&order=asc&limit=2&offset=50&cursor=${encodeURIComponent(cursor)}`, moderator)
      .expect(200);

    expect(withOffset.body.data.map((row: { id: string }) => row.id))
      .toEqual(withoutOffset.body.data.map((row: { id: string }) => row.id));
  });

  // Backward compatibility is the whole reason offset was kept: two clients
  // pass it today and neither knows about cursors yet.
  it('still answers a plain request with no cursor at all', async () => {
    const response = await harness
      .get('/submissions/admin?status=all&limit=5', moderator)
      .expect(200);
    expect(Array.isArray(response.body.data)).toBe(true);
    expect(response.body.data.length).toBeGreaterThan(0);
  });

  it('keeps a filter applied across pages', async () => {
    const { ids } = await walk('/submissions/admin?status=pending&order=asc', 2);
    // Every id returned under status=pending must actually be pending.
    for (const id of ids.slice(0, 10)) {
      const row = await harness.submission(id);
      expect(row?.status).toBe('pending');
    }
  });
});
