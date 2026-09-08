# Run Bsheel locally

Copy-paste guide for contributors. Every command here was run on a machine and
worked; where something is slow or has a trap, it says so.

You need **four terminal tabs**: services, API, worker, and one for whichever
client you are testing.

> **The accounts below are local seed fixtures**, created by
> `backend/scripts/seed-local.mjs` against your own empty database. That script
> refuses to run against anything that looks like production. These are not real
> credentials and never touch a real user.

---

## 0. Prerequisites

| Tool | Version | Note |
|---|---|---|
| Node | **24** | The backend does **not** run on Node 20. `node --version` must say 24. |
| Flutter | 3.38.5 | Matches CI. |
| PostgreSQL | 16 or 17 | |
| Redis | 7.x | |
| MinIO | any | Stands in for R2/S3 locally. |
| Xcode | 16+ | Only if you are running the iOS app. |

```bash
# macOS, if you installed Node via Homebrew's versioned formula:
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
node --version    # must print v24.x
```

Docker is **not** required, and `docker compose up` is not the path this guide
takes — the pieces run natively below.

---

## 1. Tab 1 — services

### Postgres

```bash
brew services start postgresql@17
createuser -s bsheel 2>/dev/null; createdb -O bsheel bsheel_dev 2>/dev/null
psql -d postgres -c "ALTER USER bsheel WITH PASSWORD 'bsheel';"
```

### Redis

```bash
redis-server --port 63799 --daemonize yes
redis-cli -p 63799 ping    # PONG
```

> Port **63799**, not 6379. If you already run Redis on 6379 for something
> else, this keeps the two apart.

### MinIO

```bash
mkdir -p /tmp/bsheel-minio
MINIO_ROOT_USER=bsheeldev MINIO_ROOT_PASSWORD=bsheeldevsecret \
  minio server --address 127.0.0.1:9000 --console-address 127.0.0.1:9001 \
  /tmp/bsheel-minio &
```

Create the bucket once:

```bash
cd backend && npm ci && node -e "
const {S3Client,CreateBucketCommand}=require('@aws-sdk/client-s3');
new S3Client({endpoint:'http://127.0.0.1:9000',region:'us-east-1',forcePathStyle:true,
  credentials:{accessKeyId:'bsheeldev',secretAccessKey:'bsheeldevsecret'}})
  .send(new CreateBucketCommand({Bucket:'bsheel-dev'})).then(()=>console.log('bucket ok'));"
```

Check all three:

```bash
pg_isready -h 127.0.0.1 -p 5432
redis-cli -h 127.0.0.1 -p 63799 ping
curl -s -o /dev/null -w "minio:%{http_code}\n" http://127.0.0.1:9000/minio/health/live
```

---

## 2. Tab 2 — the API

```bash
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
cd backend
cp .env.example .env        # first time only — then set DATABASE_URL/REDIS_URL below
npm ci
```

Point `.env` at what you started in tab 1:

```
DATABASE_URL=postgresql://bsheel:bsheel@127.0.0.1:5432/bsheel_dev
REDIS_URL=redis://127.0.0.1:63799
```

Then:

```bash
npm run db:migrate          # applies every migration to an empty database
npm run build               # ~2m45s. It is NOT hung. Let it finish.
set -a && . ./.env && set +a
node dist/main.js
```

> **Two things that look like hangs and are not.**
> `npm run build` takes about **2m45s**, and `NestFactory.create` takes about
> **52s** after that before the API answers. Give it two full minutes before
> concluding anything is wrong. Several people have killed it early and
> reported a stall.

Wait for readiness properly rather than guessing:

```bash
until curl -sf http://127.0.0.1:3010/api/v1/health/live >/dev/null; do sleep 3; done
curl -s http://127.0.0.1:3010/api/v1/health/ready
```

You want to see:

```json
{"success":true,"data":{"status":"ok","dependencies":{"postgres":"up","redis":"up"}}}
```

API base URL: `http://127.0.0.1:3010/api/v1` · OpenAPI at `/docs` when
`SWAGGER_ENABLED=true`.

---

## 3. Tab 3 — the worker

Background jobs: notifications, XP, the hourly media sweep. The app works
without it, but nothing asynchronous will happen.

```bash
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
cd backend && set -a && . ./.env && set +a
node dist/main.worker.js
```

---

## 4. Seed the test data

```bash
cd backend && set -a && . ./.env && set +a
node scripts/seed-local.mjs --reset
```

That creates 8 users, 15 quests and 13 submissions covering **every** review
state — approved, rejected, pending, appealed-and-pending, re-rejected,
soft-deleted and expired — plus follows, votes, comments, a block, an open
report, a Quest of the Day, a waitlist entry and a quest suggestion. There is
deliberately real data in every queue, so no screen is empty.

### Accounts

**Password for all of them: `Str0ng-Passphrase-9`**

| Email | Role | Use it to see |
|---|---|---|
| `admin@bsheel.test` | super_admin | Everything — all 21 admin pages |
| `mod@bsheel.test` | moderator | The moderation queues only (no settings/users) |
| `sami@bsheel.test` | user | **A rejected submission with an appeal still available** — the appeal row in Quest History |
| `ziad@bsheel.test` | user | A submission whose appeal is already spent (no appeal offered) |
| `omar@bsheel.test` | user | A clean account for the normal quest loop |
| `nour@bsheel.test` | user | Has a submission awaiting review |
| `rana@bsheel.test`, `layla@bsheel.test` | user | Feed and social content |

---

## 5a. Tab 4 — the admin dashboard

```bash
cd apps/admin_web
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_URL=http://127.0.0.1:3010/api/v1
```

> **`--web-port=8080` is required.** Without it Flutter picks a random port,
> which is not in the API's `CORS_ORIGINS`, and every request fails with a CORS
> error while the UI just sits there. If you must use another port, add it to
> `CORS_ORIGINS` in `backend/.env` and restart the API.

Sign in as `admin@bsheel.test`. Worth looking at first:

- **Moderation → review** — the centre of the product. Keyboard: `J`/`K` move
  through the queue, `A` approves, `R` rejects.
- **Appeals** — overturn or uphold a rejection.
- **Users** — suspend and ban flows.
- **XP** — the reconciliation audit with its drift table.

### Harmless console noise

Chrome's console will print `Found an existing <meta name="viewport"> tag…`
followed by a long stack. That is Flutter web replacing its own viewport tag on
every start. It is not an error and not worth reporting.

---

## 5b. Tab 4 — the mobile app

```bash
cd apps/mobile_app
flutter pub get
open -a Simulator          # boot a simulator BEFORE flutter run
flutter devices            # confirm your simulator is listed
flutter run --dart-define=API_URL=http://127.0.0.1:3010/api/v1
```

Debug builds fall back to `http://127.0.0.1:3010/api/v1`, so a bare
`flutter run` also works against a local API.

> **Boot the simulator first.** If Simulator.app is not already running,
> `flutter run` reports "No supported devices found" even when `xcrun simctl`
> shows a booted device.

If Xcode complains about CocoaPods:

```bash
cd apps/mobile_app/ios
rm -f Podfile.lock && pod install --repo-update
```

Sign in as `sami@bsheel.test` to reach the appeal flow, or `omar@bsheel.test`
for a clean run through the quest loop.

---

## 6. Verify before you push

```bash
cd backend
npm run lint
npm test                    # unit
npm run db:migrate          # replay from an empty database
npm run db:migrate:check    # checksum ledger
npm run db:types:check      # generated types still match the schema
npm run test:e2e            # integration — needs Postgres + Redis
npm run build
```

```bash
melos run analyze           # every package, must be zero issues
melos run test              # pure-Dart, Flutter, then admin web on Chrome
dart format --set-exit-if-changed .
```

Point integration tests at a disposable database. **Never at production.**

> `admin_web` is tested on Chrome, not the Dart VM: it imports
> `dart:js_interop`, `dart:ui_web` and `package:web`, so a bare `flutter test`
> cannot compile it. `melos run test` handles that split for you. If you run it
> by hand, use `flutter test --platform chrome`.

---

## 7. Things that will waste your time if nobody tells you

| Symptom | Cause |
|---|---|
| `npm run build` or the API "hangs" | It doesn't. ~2m45s to build, ~52s to start. Wait two minutes. |
| CORS errors in the dashboard, UI does nothing | Flutter picked a random web port. Use `--web-port=8080`. |
| `DATABASE_URL is required` | Export it, or put it in `backend/.env` — the migrate script reads that file. |
| `flutter analyze` passes but the app won't run | Analyze is not a compile. Run `flutter test` too. |
| "No supported devices found" | Boot Simulator.app before `flutter run`. |
| `git status` shows a clean tree that isn't | If `git` is erroring it prints nothing, so `git status --porcelain \| wc -l` reports `0`. **Check the exit code.** This has hidden real work more than once. |
| Push notifications do nothing | Expected without `FIREBASE_SERVICE_ACCOUNT`. Kill-switched off, and the appeal flow no longer depends on push. |
| Password reset does nothing | Expected. `EMAIL_DELIVERY_WEBHOOK_URL` is unset; no email provider is wired yet. |

---

## 8. Never commit

All are gitignored; check before you `git add -A` anyway.

`backend/.env` · `apps/mobile_app/ios/Runner/GoogleService-Info.plist` ·
`apps/mobile_app/android/app/google-services.json` ·
`apps/mobile_app/android/key.properties` · the release keystore (`*.jks`) ·
`ios/AuthKey_*.p8` · any Firebase service-account JSON (`*-adminsdk-*.json`).

The Firebase service account grants server-side access to the whole project.
Keep it outside the repo and pass it through `FIREBASE_SERVICE_ACCOUNT`.
