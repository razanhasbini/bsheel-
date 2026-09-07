// One-shot R2 cleanup Worker for the Quest App.
//
// Lists every object in the `quest-media` bucket, joins against Supabase to
// figure out which keys are still referenced by an active row (submission
// media or profile avatar), and emits / deletes the orphans. Designed to be
// deployed, run, and `wrangler delete`d in the same session.
//
// Endpoints (all require `Authorization: Bearer <admin Supabase JWT>`):
//   GET  /dry-run        — count + diff + first 50 sample orphan keys
//   GET  /orphans?cursor=  — paginate full orphan list, 1000 per page
//   POST /apply          — body: { keys: string[] } → deletes those keys
//
// Conservative policy: a submission row's media is "active" regardless of
// status (approved | pending | rejected) so we don't accidentally nuke
// rejection evidence the user might still want to appeal. Forward-fix code
// paths handle deliberate deletions; this worker only sweeps true orphans.
//
// Bindings expected (see wrangler-cleanup.toml):
//   QUEST_MEDIA                    R2 bucket
//   SUPABASE_URL                   var
//   SUPABASE_ANON_KEY              var
//   SUPABASE_SERVICE_ROLE_KEY      secret (wrangler secret put …)
//   PUBLIC_URL                     var, e.g. https://pub-….r2.dev

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return preflight();

    const admin = await verifyAdmin(env, request);
    if (!admin) return json({ error: 'Unauthorized — admin JWT required' }, 401);

    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, '').replace(/\/+$/, '');

    try {
      if (request.method === 'GET' && path === 'dry-run') {
        return json(await dryRun(env));
      }
      if (request.method === 'GET' && path === 'orphans') {
        const cursor = url.searchParams.get('cursor') || undefined;
        return json(await orphansPage(env, cursor));
      }
      if (request.method === 'POST' && path === 'apply') {
        const body = await request.json().catch(() => ({}));
        const keys = Array.isArray(body.keys) ? body.keys : [];
        return json(await applyDelete(env, keys));
      }
    } catch (err) {
      return json({ error: err.message, stack: err.stack }, 500);
    }

    return json(
      {
        error: 'Not found',
        endpoints: ['GET /dry-run', 'GET /orphans?cursor=', 'POST /apply'],
      },
      404,
    );
  },
};

// ── Auth ───────────────────────────────────────────────────────────────────

async function verifyAdmin(env, request) {
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) return null;
  const token = auth.slice('Bearer '.length);

  const userRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
    },
  });
  if (!userRes.ok) return null;
  const user = await userRes.json();
  if (!user?.id) return null;

  // Must appear in the admins table.
  const adminRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/admins?select=role&user_id=eq.${user.id}`,
    {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  if (!adminRes.ok) return null;
  const rows = await adminRes.json();
  if (!rows || rows.length === 0) return null;

  return { id: user.id, role: rows[0].role };
}

// ── Active-key set from Supabase ───────────────────────────────────────────

async function fetchActiveKeys(env) {
  const publicPrefix = env.PUBLIC_URL.replace(/\/$/, '') + '/';
  const active = new Set();

  // submissions.media_url — paginated through PostgREST Range header.
  for await (const row of paginateSupabase(env, 'submissions?select=media_url')) {
    const urls = parseMediaUrl(row.media_url);
    for (const u of urls) {
      if (u.startsWith(publicPrefix)) active.add(u.slice(publicPrefix.length));
    }
  }

  // profiles.avatar_url
  for await (const row of paginateSupabase(
    env,
    'profiles?select=avatar_url&avatar_url=not.is.null',
  )) {
    if (row.avatar_url && row.avatar_url.startsWith(publicPrefix)) {
      active.add(row.avatar_url.slice(publicPrefix.length));
    }
  }

  return active;
}

async function* paginateSupabase(env, queryPath) {
  const pageSize = 1000;
  let from = 0;
  while (true) {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/${queryPath}`, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        Range: `${from}-${from + pageSize - 1}`,
        'Range-Unit': 'items',
        Prefer: 'count=exact',
      },
    });
    if (!res.ok) {
      throw new Error(`Supabase ${queryPath}: ${res.status} ${await res.text()}`);
    }
    const rows = await res.json();
    if (!Array.isArray(rows)) {
      throw new Error(`Supabase ${queryPath}: expected array, got ${JSON.stringify(rows)}`);
    }
    for (const row of rows) yield row;
    if (rows.length < pageSize) break;
    from += pageSize;
  }
}

function parseMediaUrl(raw) {
  if (!raw) return [];
  const t = String(raw).trim();
  if (t.startsWith('[')) {
    try {
      const arr = JSON.parse(t);
      if (Array.isArray(arr)) {
        return arr.map((s) => String(s).trim()).filter(Boolean);
      }
    } catch (_) {
      // fall through — treat as bare string
    }
  }
  return [t];
}

// ── R2 listing ─────────────────────────────────────────────────────────────

async function listAllR2(env) {
  const all = [];
  let cursor = undefined;
  do {
    const page = await env.QUEST_MEDIA.list({ cursor, limit: 1000 });
    for (const o of page.objects) {
      all.push({ key: o.key, size: o.size });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return all;
}

// ── Endpoints ──────────────────────────────────────────────────────────────

async function dryRun(env) {
  const r2 = await listAllR2(env);
  const active = await fetchActiveKeys(env);

  let totalBytes = 0;
  let orphanBytes = 0;
  const orphans = [];
  for (const o of r2) {
    totalBytes += o.size;
    if (!active.has(o.key)) {
      orphans.push(o);
      orphanBytes += o.size;
    }
  }

  return {
    summary: {
      r2_objects: r2.length,
      r2_total_bytes: totalBytes,
      r2_total_mb: +(totalBytes / 1024 / 1024).toFixed(2),
      active_keys_in_db: active.size,
      orphan_count: orphans.length,
      orphan_bytes: orphanBytes,
      orphan_mb: +(orphanBytes / 1024 / 1024).toFixed(2),
    },
    sample_orphans: orphans.slice(0, 50).map((o) => o.key),
  };
}

async function orphansPage(env, cursor) {
  const active = await fetchActiveKeys(env);
  const page = await env.QUEST_MEDIA.list({ cursor, limit: 1000 });
  const orphans = page.objects
    .filter((o) => !active.has(o.key))
    .map((o) => ({ key: o.key, size: o.size }));
  return {
    orphans,
    next_cursor: page.truncated ? page.cursor : null,
  };
}

async function applyDelete(env, keys) {
  const BATCH = 50;
  let deleted = 0;
  const failures = [];
  for (let i = 0; i < keys.length; i += BATCH) {
    const slice = keys.slice(i, i + BATCH);
    const results = await Promise.allSettled(
      slice.map((k) => env.QUEST_MEDIA.delete(k)),
    );
    for (let j = 0; j < results.length; j++) {
      if (results[j].status === 'fulfilled') {
        deleted++;
      } else {
        failures.push({ key: slice[j], error: results[j].reason?.message });
      }
    }
  }
  return { requested: keys.length, deleted, failed: failures.length, failures };
}

// ── Helpers ────────────────────────────────────────────────────────────────

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders(),
    },
  });
}

function preflight() {
  return new Response(null, { headers: corsHeaders() });
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}
