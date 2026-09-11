#!/usr/bin/env node
// Provisions a business end to end (#14, #50).
//
// A business needs four things before its owner can open the dashboard, and
// missing any one of them fails in a way that looks like a bug:
//
//   1. the business itself
//   2. the places it speaks for
//   3. the owner as a member
//   4. the analytics subscription
//
// (4) is the one people forget. It is NULL by default and deliberately not
// implied by the business existing, so an owner whose account was set up
// without it signs in and gets ANALYTICS_NOT_SUBSCRIBED with nothing
// pointing at the cause.
//
// Everything here goes through the audited super_admin endpoints rather
// than writing rows directly, so the admin_audit_log entries a dispute
// would need actually exist.
//
// Dry run by default. Nothing is written without --apply.
//
//   node scripts/provision-business.mjs \
//     --api https://api.bsheel.app/api/v1 \
//     --admin-email you@example.com --admin-password '...' \
//     --name 'Tawlet Beirut' --owner theirusername \
//     --place 'Mar Mikhael' --place 'Beirut Souks' \
//     --apply

const args = process.argv.slice(2);

function flag(name) {
  return args.includes(`--${name}`);
}

function option(name, fallback = undefined) {
  const index = args.indexOf(`--${name}`);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

function options(name) {
  const found = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === `--${name}` && i + 1 < args.length) found.push(args[i + 1]);
  }
  return found;
}

const apply = flag('apply');
const api = (option('api') ?? process.env.API_URL ?? 'http://127.0.0.1:3010/api/v1').replace(/\/$/, '');
const adminEmail = option('admin-email') ?? process.env.ADMIN_EMAIL;
const adminPassword = option('admin-password') ?? process.env.ADMIN_PASSWORD;
const name = option('name');
const ownerHandle = option('owner');
const slug = option('slug');
const placeNames = options('place');
const subscribe = !flag('no-subscribe');

if (!name || !ownerHandle) {
  console.error('Required: --name "Business Name" --owner <username>');
  console.error('See the header of this file for a full example.');
  process.exit(1);
}
if (!adminEmail || !adminPassword) {
  console.error('Required: --admin-email and --admin-password (a super_admin).');
  process.exit(1);
}

let token = null;

async function call(method, path, body) {
  const response = await fetch(`${api}/${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const code = parsed?.error?.code ?? response.status;
    const message = parsed?.error?.message ?? text;
    throw new Error(`${method} ${path} → ${code}: ${message}`);
  }
  return parsed?.data ?? null;
}

async function main() {
  console.log(apply ? 'Applying.' : 'Dry run — nothing will be written. Pass --apply to act.');
  console.log(`API: ${api}`);

  const session = await call('POST', 'auth/login', {
    email: adminEmail,
    password: adminPassword,
  });
  token = session?.accessToken ?? session?.session?.accessToken;
  if (!token) throw new Error('Login succeeded but returned no access token.');

  // Resolve the owner before creating anything: a mistyped handle should
  // not leave a business behind with nobody able to manage it.
  const owner = await call('GET', `profiles/by-username/${encodeURIComponent(ownerHandle)}`);
  if (!owner?.id) throw new Error(`No account with username "${ownerHandle}".`);
  console.log(`Owner: @${owner.username} (${owner.id})`);

  // Same for the places, so a typo is reported before any write.
  const resolved = [];
  if (placeNames.length > 0) {
    const places = await call('GET', 'map/admin/places');
    const rows = Array.isArray(places) ? places : (places?.items ?? []);
    for (const wanted of placeNames) {
      const match = rows.find(
        (row) => String(row.name).toLowerCase() === wanted.toLowerCase(),
      );
      if (!match) {
        throw new Error(
          `No published place named "${wanted}". Create it first at `
          + 'Settings → Destinations in the admin console.',
        );
      }
      resolved.push({ id: match.id, name: match.name });
    }
    console.log(`Places: ${resolved.map((p) => p.name).join(', ')}`);
  } else {
    console.log('Places: none given — the dashboard will report no activity until some are claimed.');
  }

  if (!apply) {
    console.log('\nWould create the business, claim those places, add the owner,');
    console.log(subscribe ? 'and grant the analytics subscription.' : 'and NOT grant analytics (--no-subscribe).');
    return;
  }

  const business = await call('POST', 'admin/businesses', {
    name,
    ownerUserId: owner.id,
    ...(slug ? { slug } : {}),
  });
  console.log(`Created business ${business.id} (${business.slug}).`);

  for (const place of resolved) {
    await call('POST', `admin/businesses/${business.id}/places`, { placeId: place.id });
    console.log(`  claimed ${place.name}`);
  }

  // The step that is otherwise forgotten.
  if (subscribe) {
    await call('PATCH', `admin/businesses/${business.id}`, { analyticsSubscribed: true });
    console.log('  analytics subscription granted');
  } else {
    console.log('  analytics NOT granted — the owner will see ANALYTICS_NOT_SUBSCRIBED');
  }

  // Accurate in both cases: without the subscription the owner can sign
  // in and will be refused, and saying otherwise sends someone to debug a
  // dashboard that is working exactly as configured.
  console.log(
    subscribe
      ? '\nDone. The owner can now sign in and read the dashboard.'
      : '\nDone, but analytics is off: the owner can sign in and will be '
        + 'refused until you re-run with a subscription.',
  );
}

main().catch((error) => {
  console.error(`\nFailed: ${error.message}`);
  process.exit(1);
});
