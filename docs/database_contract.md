# Database Contract — Single Source of Truth

> **Read this before touching ANY database-related code. This document is the human-readable version of what `supabase_contracts` enforces in code.**

## Tables

### profiles
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | FK auth.users, cascade delete | — |
| username | text | unique, 3-30 chars, alphanumeric+underscore | — |
| display_name | text | 1-50 chars | — |
| avatar_url | text | nullable | null |
| bio | text | nullable, max 300 chars | null |
| xp | integer | >= 0 | 0 |
| level | integer | >= 1 | 1 |
| quests_completed | integer | >= 0 | 0 |
| created_at | timestamptz | not null | now() |
| updated_at | timestamptz | nullable, auto-set on update | null |

**Triggers:** Auto-created on auth.users insert. updated_at auto-set.

### quests
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | auto-generated | gen_random_uuid() |
| title | text | 3-100 chars | — |
| description | text | 10-500 chars | — |
| category | text | `fitness`, `creativity`, `social`, `learning`, `adventure` | — |
| difficulty | text | `easy`, `medium`, `hard` | — |
| xp_reward | integer | 5-100 | 10 |
| duration_hours | integer | 1-168 (admin-configurable timer) | 4 |
| is_active | boolean | not null | true |
| created_by | uuid | FK profiles, nullable, set null on delete | null |
| created_at | timestamptz | not null | now() |
| updated_at | timestamptz | nullable, auto-set | null |

### user_quests
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | auto-generated | gen_random_uuid() |
| user_id | uuid | FK profiles, cascade delete | — |
| quest_id | uuid | FK quests, cascade delete | — |
| status | text | `assigned`, `submitted`, `approved`, `rejected`, `expired` | 'assigned' |
| assigned_at | timestamptz | not null | now() |
| completed_at | timestamptz | nullable | null |
| expires_at | timestamptz | not null | set at assignment from quests.duration_hours |

**Constraints:** Only one active (assigned/submitted) quest per user (partial unique index).

### submissions
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | auto-generated | gen_random_uuid() |
| user_quest_id | uuid | FK user_quests, cascade delete, unique | — |
| user_id | uuid | FK profiles, cascade delete | — |
| media_url | text | not null | — |
| media_type | text | `image`, `video` | 'image' |
| caption | text | nullable, max 500 chars | null |
| status | text | `pending`, `approved`, `rejected` | 'pending' |
| reviewed_by | uuid | FK profiles, nullable | null |
| review_note | text | nullable, max 500 chars | null |
| submitted_at | timestamptz | not null | now() |
| reviewed_at | timestamptz | nullable | null |

**Triggers:**
- On INSERT: auto-updates user_quest status to 'submitted'
- On status UPDATE to 'approved': awards XP, increments quests_completed, creates notification
- On status UPDATE to 'rejected': updates user_quest, creates notification

### reactions
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | auto-generated | gen_random_uuid() |
| submission_id | uuid | FK submissions, cascade delete | — |
| user_id | uuid | FK profiles, cascade delete | — |
| type | text | `upvote`, `downvote` | — |
| created_at | timestamptz | not null | now() |

**Constraints:** UNIQUE (submission_id, user_id) — one vote per user per submission.
**RLS:** everyone can read votes; authenticated users can insert, update, and delete only their own votes.
**Triggers:** Auto-creates notification for submission owner on new upvote (unless self-reaction).

### notifications
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | auto-generated | gen_random_uuid() |
| user_id | uuid | FK profiles, cascade delete | — |
| title | text | 1-100 chars | — |
| body | text | 1-500 chars | — |
| type | text | `quest_assigned`, `submission_approved`, `submission_rejected`, `reaction_received`, `level_up` | — |
| reference_id | text | nullable | null |
| is_read | boolean | not null | false |
| created_at | timestamptz | not null | now() |
| actor_id | uuid | FK profiles, set null on delete | null |

### admins
| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| id | uuid PK | auto-generated | gen_random_uuid() |
| user_id | uuid | FK profiles, unique, cascade delete | — |
| role | text | `super_admin`, `moderator` | 'moderator' |
| created_at | timestamptz | not null | now() |

## RPC Functions

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| assign_random_quest | p_user_id uuid | user_quests row | Assigns random active quest; creates notification |
| get_leaderboard | p_limit int (default 50) | table (rank, user_id, username, etc.) | Top users by XP |
| get_user_xp_stats | p_user_id uuid | table (total_xp, level, xp_to_next, rank) | Single user XP breakdown |
| increment_xp | p_user_id uuid, p_amount int | void | Atomic XP add + level up check |
| expire_overdue_quests | — | void | Marks assigned quests past deadline as expired |
| get_feed | p_limit int, p_offset int | table (submission+user+quest+reaction data) | Approved submissions with joined data |

## Helper Functions (trigger-only, not client-callable)

| Function | Used By |
|----------|---------|
| handle_updated_at() | All tables with updated_at |
| handle_new_user() | Auth signup trigger |
| handle_submission_created() | Submissions INSERT |
| handle_submission_approved() | Submissions UPDATE |
| handle_reaction_created() | Reactions INSERT |
| is_admin() | RLS policies |
| is_super_admin() | RLS policies |

## Storage Buckets

| Bucket | Public | Max Size | Allowed Types | Path Pattern |
|--------|--------|----------|---------------|-------------|
| avatars | yes | 5MB | jpeg, png, webp | `{user_id}/avatar.jpg` |
| submissions | yes | 50MB | jpeg, png, webp, mp4, mov | `{user_id}/{submission_id}` |

## All Status Values (complete list)

| Context | Values |
|---------|--------|
| quests.is_active | `true`, `false` |
| quests.category | `fitness`, `creativity`, `social`, `learning`, `adventure` |
| quests.difficulty | `easy`, `medium`, `hard` |
| user_quests.status | `assigned`, `submitted`, `approved`, `rejected`, `expired` |
| submissions.status | `pending`, `approved`, `rejected` |
| submissions.media_type | `image`, `video` |
| reactions.type | `upvote`, `downvote` |
| notifications.type | `quest_assigned`, `submission_approved`, `submission_rejected`, `reaction_received`, `level_up` |
| admins.role | `super_admin`, `moderator` |

## Changing the Schema

**Any dev's AI can edit the schema**, but MUST follow this process:

1. **Check `git log` on supabase/migrations/** — see what changed recently
2. **Edit the SQL migration** — create a new numbered file in `supabase/migrations/`
3. **Update `supabase_contracts`** — add/modify constants in tables.dart, columns.dart, statuses.dart, rpc_names.dart
4. **Update `app_models`** — add/modify model fields
5. **Run `bash scripts/check_schema_drift.sh`** — verify zero drift
6. **Describe the change in your commit message** — what changed, why, impact
7. **Update this document** — keep the tables above current

