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

  /// Each row this suite owns, exactly once across the whole walk.
  ///
  /// Scoped to owned rows on purpose, and this is the third assertion in
  /// this file to learn the lesson: the list being walked is a shared table
  /// that other suites are writing to *and reordering* while the walk is in
  /// flight. `streaks` and `missing-parity` both UPDATE `submitted_at`, and
  /// moving a row's sort key mid-walk makes any correct keyset paginator
  /// return that row twice or not at all. A global
  /// `new Set(ids).size === ids.length` therefore failed without any
  /// paginator bug — 52 unique ids out of 53 — which is indistinguishable
  /// from the real thing it was meant to catch.
  ///
  /// These fixtures' sort keys are never touched, so counting their
  /// appearances tests the actual guarantee. It still catches the original
  /// bug: a cursor that fails to advance either repeats these rows or,
  /// bounded at 60 pages, never reaches them.
  const appearancesOfOwned = (ids: readonly string[]): number[] =>
    [...owned].map((id) => ids.filter((seen) => seen === id).length);

  // The bug that matters: a paginator that returns everything exactly once.
  it('covers every row exactly once across pages, ascending', async () => {
    const { ids, pages } = await walk('/submissions/admin?status=all&order=asc', 3);
    expect(pages).toBeGreaterThan(1);
    expect(appearancesOfOwned(ids)).toEqual([...owned].map(() => 1));
  });

  // The comparison has to follow the sort. Reversing one without the other
  // is the classic keyset error and it returns the first page forever.
  it('covers every row exactly once across pages, descending', async () => {
    const { ids, pages } = await walk('/submissions/admin?status=all&order=desc', 3);
    expect(pages).toBeGreaterThan(1);
    expect(appearancesOfOwned(ids)).toEqual([...owned].map(() => 1));
  });

  /// Rows that share a `submitted_at`, which is the case the tiebreaker
  /// exists for and the one that was broken.
  ///
  /// `ORDER BY s.submitted_at DESC, s.id` sorts ties by ascending id while
  /// the cursor compares the tuple `(submitted_at, id) < (at, id)`, which is
  /// a descending order on both columns. The two disagree only inside a tie
  /// group — so a page boundary falling there repeated rows or skipped them,
  /// silently, and only when timestamps collided.
  ///
  /// They collide readily: `submitted_at` defaults to `now()`, which in
  /// PostgreSQL is the transaction timestamp, so a batch written by one
  /// transaction shares it to the microsecond. This first showed up as one
  /// duplicate in a 51-row walk of the shared list — the kind of intermittent
  /// result that reads as test flakiness.
  describe('rows sharing a submitted_at', () => {
    /// Four submissions stamped with one timestamp unique to this run.
    ///
    /// Unique, not a fixed sentinel: a fixed `2000-01-01` would merge with
    /// whatever a crashed earlier run left behind, and the group would no
    /// longer be the four rows the assertions reason about. The microsecond
    /// offset comes from the row ids, so two runs cannot collide.
    ///
    /// Four with a page size of three guarantees a boundary falls *inside*
    /// the group, which is the only place the bug lives.
    const stampedGroup = async (prefix: string): Promise<{ ids: string[]; at: string }> => {
      const ids: string[] = [];
      const user = await harness.createUser({ prefix });
      for (let index = 0; index < 4; index += 1) {
        const submission = await harness.createSubmission(user, { caption: `tie ${prefix} ${index}` });
        ids.push(submission.id);
      }
      const stamped = await harness.database.query<{ at: string }>(
        `UPDATE submissions
         SET submitted_at = date_trunc('second', now()) + make_interval(secs => $2::numeric)
         WHERE id = ANY($1::uuid[])
         RETURNING to_char(submitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.USZ') AS at`,
        [ids, Number.parseInt(ids[0].slice(0, 6), 16) / 1_000_000],
      );
      return { ids, at: stamped.rows[0].at };
    };

    /// Walks the list until every id in `group` has been seen, and reports how
    /// many times each appeared.
    ///
    /// Position-independent on purpose. Asserting "the group is on the first
    /// two pages" would depend on where the stamp landed relative to whatever
    /// the other parallel suites are writing, and asserting global uniqueness
    /// over the whole walk would fail on a concurrent insert that is nobody's
    /// bug. Counting appearances of *these* ids is the actual property: a
    /// keyset paginator must return each row it covers exactly once.
    const countAppearances = async (
      order: 'asc' | 'desc',
      group: readonly string[],
    ): Promise<Map<string, number>> => {
      const counts = new Map(group.map((id) => [id, 0]));
      let cursor: string | undefined;
      for (let page = 0; page < 60; page += 1) {
        const query = `/submissions/admin?status=all&order=${order}&limit=3`
          + (cursor ? `&cursor=${encodeURIComponent(cursor)}` : '');
        const response = await harness.get(query, moderator).expect(200);
        const rows = response.body.data as { id: string; next_cursor: string | null }[];
        for (const row of rows) {
          if (counts.has(row.id)) counts.set(row.id, counts.get(row.id)! + 1);
        }
        const next = rows.at(-1)?.next_cursor ?? null;
        // Stop as soon as the whole group has been seen at least once; the
        // walk only needs to cover the group, not the shared table.
        if (!next || [...counts.values()].every((count) => count > 0)) break;
        cursor = next;
      }
      return counts;
    };

    // The direction the bug was in: the sort put ties in ascending id order
    // while the cursor excluded by descending tuple.
    it('returns each tied row exactly once when paging descending', async () => {
      const { ids } = await stampedGroup('tiedesc');
      const counts = await countAppearances('desc', ids);
      expect([...counts.values()]).toEqual([1, 1, 1, 1]);
    });

    // The control case. Ascending already agreed with an ascending id
    // tiebreaker, so this cannot fail for the original bug — it is here so
    // that a future "fix" which flips the tiebreaker the other way breaks
    // something instead of trading one direction's correctness for the
    // other's.
    it('returns each tied row exactly once when paging ascending', async () => {
      const { ids } = await stampedGroup('tieasc');
      const counts = await countAppearances('asc', ids);
      expect([...counts.values()]).toEqual([1, 1, 1, 1]);
    });
  });

  it('returns the same set of rows by cursor as by offset', async () => {
    const byCursor = await walk('/submissions/admin?status=all&order=asc', 3);
    const byOffset: string[] = [];
    // Walks until this suite's own rows have all been seen, rather than to a
    // fixed offset. The list is a shared table that every other suite adds
    // to, so a hard ceiling of 60 rows silently stopped covering these
    // fixtures the moment the corpus grew past it — and the failure read as
    // "the offset paginator lost a row" when the offset walk had simply
    // never reached it. The 20-page bound is the runaway guard, not the
    // coverage target.
    for (let page = 0; page < 20; page += 1) {
      const response = await harness
        .get(`/submissions/admin?status=all&order=asc&limit=20&offset=${page * 20}`, moderator)
        .expect(200);
      byOffset.push(...response.body.data.map((row: { id: string }) => row.id));
      const seen = new Set(byOffset);
      if (response.body.data.length < 20 || [...owned].every((id) => seen.has(id))) break;
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

  // Direction is half of what an ordering is, so a cursor minted ascending
  // describes a boundary the descending comparison reads backwards — and
  // returns the rows the client just walked past, with no error.
  it('refuses a cursor issued for the other sort direction', async () => {
    const ascending = await harness
      .get('/submissions/admin?status=all&order=asc&limit=2', moderator)
      .expect(200);
    const cursor = ascending.body.data.at(-1)?.next_cursor;
    expect(cursor).toBeTruthy();

    await harness
      .get(`/submissions/admin?status=all&order=desc&limit=2&cursor=${encodeURIComponent(cursor)}`, moderator)
      .expect(400);
    // And still works in the direction it was issued for.
    await harness
      .get(`/submissions/admin?status=all&order=asc&limit=2&cursor=${encodeURIComponent(cursor)}`, moderator)
      .expect(200);
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

    // A row that has since vanished is not a filter violation. Other suites
    // delete their fixtures on the way out, so a submission can be returned
    // by the walk and gone by the time it is looked up — which failed here as
    // `expected undefined to be 'pending'`, reading like the filter had let a
    // non-pending row through when nothing of the sort had happened.
    let checked = 0;
    for (const id of ids.slice(0, 10)) {
      const row = await harness.submission(id);
      if (!row) continue;
      expect(row.status, `row ${id} came back under status=pending`).toBe('pending');
      checked += 1;
    }

    // This suite's own fixtures are pending and are never deleted mid-run, so
    // they guarantee the assertion above actually ran against something.
    for (const id of owned) expect(ids).toContain(id);
    expect(checked).toBeGreaterThan(0);
  });
});
