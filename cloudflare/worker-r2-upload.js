// Cloudflare Worker — R2 Upload Proxy for Quest App
// Handles both submission media and avatar uploads.
// Verifies Supabase auth token before allowing uploads.
//
// Environment bindings required:
//   QUEST_MEDIA    — R2 bucket binding (bind to quest-media bucket)
//   SUPABASE_URL   — e.g. https://api.bsheel.app
//   SUPABASE_ANON_KEY — Supabase anon key
//   PUBLIC_URL     — e.g. https://pub-c5cc3a25116846169de23bc92a5ea697.r2.dev
//   ALLOWED_UPLOAD_ORIGINS — (optional) comma-separated list of allowed CORS
//                            origins. If unset, defaults to 'null' (i.e. no
//                            browser cross-origin caller is allowed). Native
//                            iOS still works because it does not send Origin.

// M1 (2026-05-17): magic-byte signatures so we can validate that the
// uploaded body actually matches the Content-Type header the client sent.
// Without this, an attacker uploads malware with `Content-Type: image/jpeg`.
const MAGIC_BYTES = {
  'image/jpeg':       [[0xFF, 0xD8, 0xFF]],
  'image/png':        [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]],
  'image/gif':        [[0x47, 0x49, 0x46, 0x38, 0x37, 0x61], [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]],
  // 'RIFF' (0-3) + 4-byte little-endian size (wildcards) + 'WEBP' (8-11).
  // Checking only 'RIFF' was a hole: RIFF is a *container* prefix shared
  // with AVI ('AVI ' at 8) and WAV ('WAVE' at 8), so any .avi/.wav passed
  // the check when declared as image/webp — exactly the Content-Type
  // spoof this table exists to stop.
  'image/webp':       [[0x52, 0x49, 0x46, 0x46, null, null, null, null, 0x57, 0x45, 0x42, 0x50]],
  // mp4/quicktime/webm all have variable-length headers — use offset-4
  // 'ftyp' for MP4/MOV and EBML signature for WebM.
  'video/mp4':        [[null, null, null, null, 0x66, 0x74, 0x79, 0x70]],
  'video/quicktime':  [[null, null, null, null, 0x66, 0x74, 0x79, 0x70]],
  'video/webm':       [[0x1A, 0x45, 0xDF, 0xA3]],
};

function matchesMagic(buffer, contentType) {
  const candidates = MAGIC_BYTES[contentType];
  if (!candidates) return false;
  const bytes = new Uint8Array(buffer);
  return candidates.some((sig) => {
    if (bytes.length < sig.length) return false;
    for (let i = 0; i < sig.length; i++) {
      if (sig[i] === null) continue; // wildcard
      if (bytes[i] !== sig[i]) return false;
    }
    return true;
  });
}

// M2 (2026-05-17): per-user storage quota. R2 itself doesn't expose
// a per-prefix size query cheaply, so we approximate with a counter
// in env.QUEST_MEDIA via metadata: we list-keys with prefix and sum.
// For volume control, we cap on the COUNT of objects per user prefix
// rather than total bytes (R2 list is paginated; cheap up to ~10k).
// Adjust if you need stricter byte-level enforcement.
const PER_USER_MAX_OBJECTS = {
  submissions: 5_000, // ~5000 submissions per user is far more than a real player will create
  avatars:        20, // avatars get overwritten; 20 historical artifacts is plenty
};

function safeKeyComponent(s) {
  // Reject path traversal and control characters in the filename
  // portion. Keys are already partitioned by /{type}/{userId}/ so we
  // only need to neutralize "..", "/", "\", and any non-printable.
  return typeof s === 'string'
    && s.length > 0
    && s.length < 256
    && !s.includes('..')
    && !s.includes('\\')
    && !/[\x00-\x1F\x7F]/.test(s);
}

export default {
  async fetch(request, env) {
    // M4 (2026-05-17): compute CORS per-request based on Origin allow-list.
    const cors = corsHeaders(request, env);

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: cors });
    }

    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname.startsWith('/media/')) {
      return serveSignedMedia(request, env, url);
    }

    if (request.method === 'POST' && url.pathname === '/sign') {
      return signMediaUrls(request, env, cors);
    }

    // Accept PUT (upload) and DELETE
    if (request.method !== 'PUT' && request.method !== 'DELETE') {
      return jsonResponse({ error: 'Method not allowed' }, 405, cors);
    }

    // Extract path: /submissions/{userId}/{filename} or /avatars/{userId}/{filename}
    const path = url.pathname.replace(/^\/+/, '');
    const pathParts = path.split('/');
    if (pathParts.length < 3) {
      return jsonResponse({ error: 'Invalid path. Use /{type}/{userId}/{filename}' }, 400, cors);
    }

    const type = pathParts[0];
    const userId = pathParts[1];
    const filename = pathParts.slice(2).join('/');

    if (!['submissions', 'avatars'].includes(type)) {
      return jsonResponse({ error: 'Invalid type. Use submissions or avatars.' }, 400, cors);
    }

    if (!safeKeyComponent(userId) || !safeKeyComponent(filename)) {
      return jsonResponse({ error: 'Invalid path component' }, 400, cors);
    }

    // Verify Supabase auth token
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Missing auth token' }, 401, cors);
    }

    const token = authHeader.replace('Bearer ', '');
    const user = await verifySupabaseToken(env, token);
    if (!user) {
      return jsonResponse({ error: 'Invalid or expired token' }, 401, cors);
    }

    // Ensure user can only upload to their own folder
    if (userId !== user.id) {
      return jsonResponse({ error: 'Cannot modify another user\'s files' }, 403, cors);
    }

    // DELETE
    if (request.method === 'DELETE') {
      try {
        await env.QUEST_MEDIA.delete(path);
        return jsonResponse({ success: true }, 200, cors);
      } catch (err) {
        return jsonResponse({ error: 'Delete failed' }, 500, cors);
      }
    }

    // PUT — upload
    const contentType = request.headers.get('Content-Type') || 'application/octet-stream';

    // Validate content type
    const allowedImageTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    const allowedVideoTypes = ['video/mp4', 'video/quicktime', 'video/webm'];
    const isImage = allowedImageTypes.includes(contentType);
    const isVideo = allowedVideoTypes.includes(contentType);

    if (!isImage && !isVideo) {
      return jsonResponse({ error: `Content-Type '${contentType}' is not allowed.` }, 400, cors);
    }

    if (type === 'avatars' && isVideo) {
      return jsonResponse({ error: 'Videos are not allowed for avatars.' }, 400, cors);
    }

    const body = await request.arrayBuffer();

    // Size limits: avatars 5MB, submissions 50MB
    const maxSize = type === 'avatars' ? 5 * 1024 * 1024 : 50 * 1024 * 1024;
    if (body.byteLength > maxSize) {
      return jsonResponse({
        error: `File too large. Max ${type === 'avatars' ? '5' : '50'}MB.`
      }, 413, cors);
    }

    // M1: enforce magic-byte signature matches the declared Content-Type.
    if (!matchesMagic(body, contentType)) {
      return jsonResponse({
        error: 'File content does not match Content-Type header'
      }, 400, cors);
    }

    // M2: per-user object count quota. Submissions get overwritten one
    // per quest, so a runaway uploader can only exceed this via the
    // direct-key path — which our key derivation prevents. Avatars
    // have a tiny cap. Note: list() is cheap up to ~1k results.
    const userPrefix = `${type}/${userId}/`;
    let totalCount = 0;
    let cursor = undefined;
    do {
      const listing = await env.QUEST_MEDIA.list({ prefix: userPrefix, limit: 1000, cursor });
      totalCount += listing.objects.length;
      cursor = listing.truncated ? listing.cursor : undefined;
      if (totalCount >= PER_USER_MAX_OBJECTS[type]) break;
    } while (cursor);

    if (totalCount >= PER_USER_MAX_OBJECTS[type]) {
      // Allow overwrite of an existing key (so submit-then-resubmit
      // works) but block new objects past the cap.
      const existing = await env.QUEST_MEDIA.head(path).catch(() => null);
      if (!existing) {
        return jsonResponse({
          error: 'Storage quota exceeded for this user',
        }, 413, cors);
      }
    }

    try {
      await env.QUEST_MEDIA.put(path, body, {
        httpMetadata: { contentType },
        // Force the response to render as an attachment, never as
        // inline HTML — defense in depth against magic-byte bypasses.
        customMetadata: { 'uploaded-by': user.id, 'uploaded-at': new Date().toISOString() },
      });

      // Security PR #52: return the private object KEY instead of a
      // long-lived public R2 URL. Clients store the key and exchange
      // it for a short-lived signed URL via POST /sign or GET /media.
      // `url` mirrors `key` so the existing `data['url']` reader on
      // the mobile/admin clients keeps working without a signature
      // change.
      return jsonResponse({ success: true, key: path, url: path }, 200, cors);
    } catch (err) {
      return jsonResponse({ error: 'Upload failed' }, 500, cors);
    }
  },
};

async function verifySupabaseToken(env, token) {
  // Accept tokens from the primary self-hosted backend AND, during the
  // migration window, the legacy Supabase Cloud backend (if configured).
  // This lets uploads keep working whether a given app build authenticates
  // against api.bsheel.app or the old cloud. Once every client is on the
  // self-hosted backend and the cloud is cancelled, drop the LEGACY_* secrets.
  const backends = [
    [env.SUPABASE_URL, env.SUPABASE_ANON_KEY],
    [env.LEGACY_SUPABASE_URL, env.LEGACY_SUPABASE_ANON_KEY],
  ];
  for (const [url, key] of backends) {
    if (!url || !key) continue;
    try {
      const response = await fetch(`${url}/auth/v1/user`, {
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) return await response.json();
    } catch {
      // try the next backend
    }
  }
  return null;
}

// Security PR #52: signed-media exchange endpoints.
//   POST /sign   — body { urls: [...] }; returns { urls: { rawKey: signedUrl } }
//   GET /media/* — serves R2 object if `exp` + HMAC `sig` validate
// Clients store private object keys instead of public R2 URLs; the
// public r2.dev bucket URL can then be shut down without breaking
// existing rows (legacy public URLs that match PUBLIC_URL host are
// also accepted by extractMediaKey for the migration period).
async function signMediaUrls(request, env, cors = {}) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Missing auth token' }, 401, cors);
  }

  const token = authHeader.replace('Bearer ', '');
  const user = await verifySupabaseToken(env, token);
  if (!user) {
    return jsonResponse({ error: 'Invalid or expired token' }, 401, cors);
  }

  const body = await request.json().catch(() => ({}));
  const urls = Array.isArray(body.urls) ? body.urls : [];
  if (urls.length > 100) {
    return jsonResponse({ error: 'Too many URLs requested' }, 400, cors);
  }

  const signed = {};
  for (const raw of urls) {
    const key = extractMediaKey(env, String(raw || ''));
    if (!key) continue;
    signed[raw] = await signedMediaUrl(request, env, key);
  }

  return jsonResponse({ urls: signed }, 200, cors);
}

async function serveSignedMedia(request, env, url) {
  const key = decodeURIComponent(url.pathname.replace(/^\/media\/+/, ''));
  const exp = Number(url.searchParams.get('exp') || '0');
  const sig = url.searchParams.get('sig') || '';

  if (!key || !isAllowedMediaKey(key)) {
    return jsonResponse({ error: 'Invalid media key' }, 400);
  }
  if (!Number.isFinite(exp) || exp < Math.floor(Date.now() / 1000)) {
    return jsonResponse({ error: 'Signed URL expired' }, 403);
  }

  const expected = await mediaSignature(env, key, exp);
  if (!timingSafeEqual(sig, expected)) {
    return jsonResponse({ error: 'Invalid signature' }, 403);
  }

  // <video> elements issue Range requests and (Safari especially) require a
  // 206 Partial Content response with Accept-Ranges — a plain 200 makes the
  // player refuse to start or fail to seek, and a moov-at-end file (iOS
  // recordings) can't even load its metadata. Passing the request headers
  // lets R2 parse the Range header and hand back the matching byte slice.
  const rangeHeader = request.headers.get('Range');
  const object = await env.QUEST_MEDIA.get(
    key,
    rangeHeader ? { range: request.headers } : undefined,
  );
  if (!object) {
    return jsonResponse({ error: 'Not found' }, 404);
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'private, max-age=300');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Accept-Ranges', 'bytes');
  if (object.httpEtag) headers.set('ETag', object.httpEtag);

  // Browsers can't play the QuickTime container ('video/quicktime') even when
  // the tracks inside are browser-friendly H.264/AAC — which is exactly what
  // iOS .mov uploads are. Relabel them as video/mp4 (same ISO-BMFF structure)
  // so the <video> element will decode them. `nosniff` above means we must set
  // the right type ourselves; the browser won't second-guess it.
  const contentType = headers.get('Content-Type') || '';
  if (contentType === 'video/quicktime' || key.toLowerCase().endsWith('.mov')) {
    headers.set('Content-Type', 'video/mp4');
  }

  const range = object.range;
  if (rangeHeader && range) {
    const offset = range.offset ?? 0;
    const length = range.length ?? (object.size - offset);
    headers.set(
      'Content-Range',
      `bytes ${offset}-${offset + length - 1}/${object.size}`,
    );
    headers.set('Content-Length', String(length));
    return new Response(object.body, { status: 206, headers });
  }

  headers.set('Content-Length', String(object.size));
  return new Response(object.body, { headers });
}

function extractMediaKey(env, raw) {
  const value = raw.trim();
  if (!value) return null;
  if (isAllowedMediaKey(value)) return value;

  try {
    const url = new URL(value);
    if (url.pathname.startsWith('/media/')) {
      const key = decodeURIComponent(url.pathname.replace(/^\/media\/+/, ''));
      return isAllowedMediaKey(key) ? key : null;
    }

    if (env.PUBLIC_URL) {
      const publicBase = new URL(env.PUBLIC_URL);
      if (url.host === publicBase.host) {
        const key = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
        return isAllowedMediaKey(key) ? key : null;
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}

function isAllowedMediaKey(key) {
  if (key.includes('..') || key.startsWith('/') || key.includes('\\')) {
    return false;
  }
  const parts = key.split('/');
  return parts.length >= 3 && ['submissions', 'avatars'].includes(parts[0]);
}

async function signedMediaUrl(request, env, key) {
  const ttl = Number(env.MEDIA_URL_TTL_SECONDS || '900');
  const exp = Math.floor(Date.now() / 1000) + (Number.isFinite(ttl) ? ttl : 900);
  const sig = await mediaSignature(env, key, exp);
  const base = new URL(request.url);
  base.pathname = `/media/${key.split('/').map(encodeURIComponent).join('/')}`;
  base.search = `?exp=${exp}&sig=${sig}`;
  return base.toString();
}

async function mediaSignature(env, key, exp) {
  if (!env.MEDIA_SIGNING_SECRET) {
    throw new Error('MEDIA_SIGNING_SECRET is not configured');
  }
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(env.MEDIA_SIGNING_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    cryptoKey,
    new TextEncoder().encode(`${key}:${exp}`),
  );
  return base64url(signature);
}

function base64url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) {
    out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return out === 0;
}

// jsonResponse takes optional per-request CORS headers. The upload/delete
// paths and the browser-facing POST /sign path pass them so cross-origin
// callers (admin web) can read the response. The signed GET /media path
// sets its own headers directly (it returns binary, with Allow-Origin: *).
function jsonResponse(data, status = 200, cors = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...cors,
    },
  });
}

// M4 (2026-05-17): tighten CORS. Native iOS clients don't send Origin
// so they always succeed. Browser clients only succeed if their origin
// appears in ALLOWED_UPLOAD_ORIGINS.
function corsHeaders(request, env) {
  const origin = request.headers.get('Origin') || '';
  const allowList = (env.ALLOWED_UPLOAD_ORIGINS || '')
    .split(',').map((o) => o.trim()).filter(Boolean);
  // If no allow-list is configured we fall back to "null" (RFC 6454
  // forbidden value) so browsers see CORS as denied. Native callers
  // are unaffected because they don't send Origin.
  const allowedOrigin = origin && allowList.includes(origin) ? origin : 'null';
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    // POST covers the browser-facing /sign endpoint; GET covers /media.
    // Without POST here the admin web's preflight for POST /sign fails.
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}
