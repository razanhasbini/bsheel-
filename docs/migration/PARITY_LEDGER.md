# Parity ledger

Status meanings: `REFERENCE` = source fully retained and identified; `IMPLEMENTED` = new code exists but is not parity-certified; `VERIFIED` = automated parity evidence exists; `BLOCKED` = documented external dependency.

| Domain / behavior | Legacy authority | New contract | Status |
|---|---|---|---|
| Password signup/login/session/logout/recovery | Supabase Auth; mobile/admin auth repositories | `/api/v1/auth/*` | IMPLEMENTED (one-time encrypted recovery tokens + retryable email worker; Flutter recovery link/token adapter fixture and mobile route wiring passed; live email-provider journey pending) |
| Google and Apple identity linking | `supabase_auth_repository.dart`, social buttons | `/api/v1/auth/oauth` | IMPLEMENTED (official server-side token verification; live provider fixtures and Flutter adapter pending) |
| Profile CRUD/onboarding/username reservation | profiles migrations and repository | `/api/v1/profiles/*` | IMPLEMENTED (media signing pending) |
| Age gate and analytics consent | migration 0142, consent controller | profile/auth commands | IMPLEMENTED (signup gate only) |
| Account suspension/ban | migrations 0068/0123; account provider/admin | profile/admin commands | IMPLEMENTED (self-read only) |
| Self-delete queue and GDPR export | migrations 0091/0122/0128/0141 | `/api/v1/account/*` + async jobs | IMPLEMENTED (idempotent worker + private R2 export; real R2 fixture pending) |
| Quest CRUD and bulk import | quests table/repository/admin pages | `/api/v1/quests/admin*` | IMPLEMENTED (single/bulk create, update, audited delete, and legacy cascade integration passed; Flutter admin adapter pending) |
| Picker, targeted injections, assignment | latest 0119 + 0137 functions; quest repository | `/api/v1/quests/picker`, `/assign` | IMPLEMENTED (picker/assignment HTTP integration + Flutter wire-contract fixtures passed; targeted-injection client fixture pending) |
| Active/history/expiry | quest repository, expiry migrations | `/api/v1/quests/active`, `/history`, `/expire` | IMPLEMENTED (HTTP integration passed; Flutter contract test pending) |
| Five rerolls per rolling 24h | migration 0124, home extras | `/api/v1/quests/rerolls*` | IMPLEMENTED |
| Quest of the day | migration 0139, mobile/admin QOTD | public quest query + `/api/v1/admin/qotd` | IMPLEMENTED |
| Following active questers | migration 0138 | `/api/v1/quests/following-active` | IMPLEMENTED |
| Proof upload and private signed media | submissions repository, R2 workers | `/api/v1/media/*` + submissions | IMPLEMENTED (real R2 integration fixture pending) |
| Submission timing and one-pending guards | migrations 0059/0140; submit page | submission create command | IMPLEMENTED |
| Moderation approve/reject/notes | latest admin RPCs, Telegram review | admin submission commands | IMPLEMENTED (HTTP + Telegram callback integration passed; Flutter adapter pending) |
| One-time appeal and deleted-post guard | canonical appeal + 0149 | submission appeal command | IMPLEMENTED |
| XP award/revoke/level transitions | 0054/0110/0113/0132 | moderation transaction | IMPLEMENTED (approve, self-delete, and audited admin-delete integration passed) |
| Global/following feed and hot sort | canonical `get_feed` + 0149 | `/api/v1/feed` | IMPLEMENTED (signed-media client adapter pending) |
| Visibility and soft delete | 0049/0114/0133 | submission visibility command | IMPLEMENTED (`visible`, `hidden_from_feed`, `deleted` integration passed) |
| Reactions and milestones | 0092/0103/0137 | reaction command/events | VERIFIED (transaction/event integration + Flutter validation and wire-contract fixture passed) |
| Comments, replies, mentions | 0018/0085/0118 | comments API/events | IMPLEMENTED (Flutter comment/mention adapters are wired in Nest mode and legacy client notification fanout is suppressed to prevent duplicates; full DB/Flutter parity fixtures pending) |
| Follow/unfollow and notification | follows repository + 0137 copy | social follow command | VERIFIED (idempotent command/notification integration + Flutter state/count/mutation contract fixture passed) |
| Block/unblock and feed exclusion | 0069 + canonical feed | social block command | IMPLEMENTED |
| Reports and abuse rate limits | 0069/0120/0137 | reports command/admin queue | IMPLEMENTED |
| Saved posts and joined quest view | 0086/0120 | saved-post API | IMPLEMENTED |
| Saved quests | 0115 | saved-quest API | VERIFIED (state/mutation integration + Flutter idempotent route contract fixture passed) |
| Search/debounce result contract | search repository/provider | `/api/v1/search` | IMPLEMENTED |
| Global/following leaderboard and XP stats | 0062/0064/0081 | `/api/v1/leaderboard`, `/api/v1/profiles/me/xp-stats` | IMPLEMENTED (HTTP integration passed; Flutter contract test pending) |
| Collab create/join/status/abandon | 0071/0072/0096/0137 | `/api/v1/collab/*` | IMPLEMENTED |
| Public collab voting/unvote | 0094/0097/0120/0149 | collab vote commands | IMPLEMENTED |
| In-app notifications/read state | notifications repository | `/api/v1/notifications/*` | IMPLEMENTED |
| FCM tokens, push fanout, cleanup | private token migrations/send-push | encrypted device API + BullMQ push worker | IMPLEMENTED (worker/unit/bootstrap passed; live Firebase fixture pending) |
| Announcements and automatic copies | 0067/0098/0137/0149 | `/api/v1/admin/notifications` + templates | IMPLEMENTED (durable push fanout; live Firebase fixture pending) |
| Telegram moderation/daily summary | edge functions + 0106/0107/0125 | `/api/v1/integrations/telegram/webhook` + BullMQ jobs | IMPLEMENTED (outbound signup/report/submission events, authenticated idempotent webhook, legacy admin commands/FSM, canonical moderation transactions, Bot API fixture, and 06:00 UTC summary scheduler passed; live Telegram fixture pending) |
| Waitlist and web quest suggestions | migration 0146 + admin pages | `/api/v1/public/*`, `/api/v1/admin/{waitlist,suggestions}` | IMPLEMENTED |
| Maintenance/app config | 0084/0108/0149 | `/api/v1/config`, `/api/v1/admin/config` | VERIFIED (public/admin HTTP integration + Flutter pre-auth scalar/config route fixtures passed; mobile uses non-overlapping five-second flag polling) |
| Realtime submission/notification updates | 0082/0145 + providers | authenticated Socket.IO events | IMPLEMENTED (JWT gateway + BullMQ/Redis cross-instance fanout + user-room isolation integration passed; typed Flutter client and mobile post/feed/profile/submission/notification/shell invalidation wiring passed analysis; quest assignment/expiry now emit durable user-room events; full journey fixture pending) |

No `IMPLEMENTED` row may be called `VERIFIED` until it has database integration tests and a Flutter contract fixture. The application must remain on the legacy backend until the required user journeys are all verified.

Flutter wire fixtures live in `packages/app_repositories/test/api_repository_contract_test.dart`; transport/refresh and auth compatibility fixtures live beside it. They assert versioned paths, request bodies, response envelopes, legacy model mapping, and client-side validation without contacting Supabase.
