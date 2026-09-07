# Migrations

Applied by **scripts/server-deploy.sh** on the Contabo box: every top-level
`*.sql` here is rsynced to the server and executed once, tracked **by
filename** in `public._applied_migrations`. (We self-host — the Supabase CLI
is NOT the migration runner.)

## Layout

- **Top level** — pending / recently-added migrations. Currently:
  `0146_website_waitlist_and_quest_suggestions.sql`,
  `0147_selfhost_functions_url.sql`,
  `0148_fix_handle_new_user_gen_random.sql`,
  `0149_repair_voting_appeals_feed_config_and_caps.sql`.
- **`applied/`** — the frozen history: 146 migrations already executed
  on prod. The deploy script only globs top-level files, so nothing in
  `applied/` ever runs again — but their filenames are recorded in
  `_applied_migrations`, so NEVER rename or renumber them, and never move a
  file back to the top level.

## Adding a migration

Create `NNNN_short_description.sql` at the TOP LEVEL with the next number
(`0150_...`). Push to main — the deploy workflow applies it.
Once it has run in prod you may move it into `applied/` on a later commit.

**Wrap it in `BEGIN; ... COMMIT;`.** `scripts/server-deploy.sh` invokes psql
*without* `--single-transaction`, so statements otherwise autocommit
individually: a failure at statement N leaves 1..N-1 committed AND the
filename unrecorded, so the next deploy replays the whole file over a
half-migrated database. An explicit transaction makes it all-or-nothing.
(Skip the wrapper only for statements that cannot run inside a transaction,
e.g. `CREATE INDEX CONCURRENTLY`.)

## Rebuilding a fresh environment

Don't replay 146 files — use a baseline:
1. Generate one on the server: `scripts/dump_schema_baseline.sh` (see its
   header for the full 3-step restore procedure, including seeding
   `_applied_migrations` so the deploy script skips history).
2. Apply the baseline, then let the deploy script run anything newer.

Numbering quirks in the history (harmless, keep as-is): `0028`+`0028b`,
two files sharing prefix `0119` (applied alphabetically), and **no `0144`
at all** — the number was never used, so the sequence jumps 0143 → 0145.

Canonical bodies of frequently-redefined RPCs live in
`../functions_canonical/` — edit there first, then **copy the body inline**
into the migration. `\i` includes do NOT work here; see that directory's
README for why.

## Reissuing an existing function — read this first

Redefining a long-lived RPC is where this repo has repeatedly hurt itself.
`CREATE OR REPLACE` silently accepts a body that has quietly lost a check
added by a *later* migration than the one you copied from. Three real
regressions, all found on 2026-08-04:

| Function | What was lost | Where it went | Symptom |
|---|---|---|---|
| `vote_collab` | `ON CONFLICT` target after 0094 dropped the 2-col unique | 0120 → 0123 | **Every** collab vote raised 42P10 |
| `appeal_submission` | 0119's `set_config('app.bypass_submission_guard')` | 0140 | **Every** non-admin appeal blocked by the 0114/0133 owner guard |
| `get_feed` | 0069's `blocked_users` anti-join | 0073 onward | Blocking a user had no effect on the feed |

Before you reissue a function:

1. `grep -rn '<function_name>' supabase/migrations` and read **every** hit —
   the newest definition is the live one, which is often not the one the
   docs point at.
2. Diff your new body against that newest one and justify every removed line.
3. Check that any `ON CONFLICT (...)` still matches a real unique index —
   arbiter inference resolves at plan time and fails at runtime, so it will
   pass migration and break in production.

## Index of applied history (by domain)

### Core schema (profiles, quests, submissions) (40)

- `applied/0001_profiles.sql`
- `applied/0002_quests.sql`
- `applied/0003_user_quests.sql`
- `applied/0004_submissions.sql`
- `applied/0014_assign_specific_quest.sql`
- `applied/0015_fix_assign_quest_expired.sql`
- `applied/0021_profile_fcm_token.sql`
- `applied/0025_fix_quest_assignment_submitted.sql`
- `applied/0026_quest_duration_hours.sql`
- `applied/0028b_quest_generation_rules.sql`
- `applied/0037_quest_timer_warning.sql`
- `applied/0041_feed_rpc_add_quest_fields.sql`
- `applied/0042_get_submission_detail_rpc.sql`
- `applied/0044_submission_detail_add_bio.sql`
- `applied/0046_fix_assign_specific_quest_submitted.sql`
- `applied/0047_drop_unique_active_user_quest.sql`
- `applied/0049_submission_visibility.sql`
- `applied/0052_appeal_submission_rpc.sql`
- `applied/0053_submission_detail_add_visibility.sql`
- `applied/0055_drop_user_quests_insert_own.sql`
- `applied/0056_expire_user_quest_rpc.sql`
- `applied/0058_fix_submission_detail_visibility.sql`
- `applied/0059_fix_submissions_insert_ownership.sql`
- `applied/0075_fix_feed_ambiguous_submission_id.sql`
- `applied/0076_submission_detail_add_collab.sql`
- `applied/0078_admin_quest_injections.sql`
- `applied/0082_enable_realtime_submissions_notifications.sql`
- `applied/0083_profile_completed_flag.sql`
- `applied/0087_allow_quest_retake.sql`
- `applied/0088_add_quest_id_to_submission_detail.sql`
- `applied/0093_fix_get_submission_detail_ambiguity.sql`
- `applied/0105_submissions_telegram_message_id.sql`
- `applied/0109_quest_injection_isolation.sql`
- `applied/0115_saved_quests.sql`
- `applied/0119_admin_quest_picker_pool.sql`
- `applied/0125_telegram_review_submission.sql`
- `applied/0129_assign_quest_cooldown.sql`
- `applied/0134_get_submission_detail_lateral.sql`
- `applied/0138_get_following_active_quests.sql`
- `applied/0139_quest_of_the_day.sql`

### Social (feed, reactions, comments, follows, collab) (30)

- `applied/0005_reactions.sql`
- `applied/0018_comments.sql`
- `applied/0019_follows.sql`
- `applied/0020_comments_update_policy.sql`
- `applied/0023_add_new_follower_notification_type.sql`
- `applied/0024_add_comment_notification_type.sql`
- `applied/0034_fix_feed_rpc.sql`
- `applied/0043_feed_rpc_add_bio.sql`
- `applied/0060_fix_comment_reply_validation.sql`
- `applied/0065_fix_feed_reaction_count.sql`
- `applied/0071_collab_tables.sql`
- `applied/0072_collab_rpcs.sql`
- `applied/0073_feed_collab_fields.sql`
- `applied/0074_collab_notifications.sql`
- `applied/0077_feed_collab_members_add_bio.sql`
- `applied/0081_get_following_leaderboard.sql`
- `applied/0085_comment_replies.sql`
- `applied/0089_hot_score_feed.sql`
- `applied/0090_feed_server_side_sort.sql`
- `applied/0092_reaction_system_fixes.sql`
- `applied/0094_public_collab_voting.sql`
- `applied/0096_join_collab_while_submitted.sql`
- `applied/0097_vote_collab_require_approved.sql`
- `applied/0102_reactions_update_policy.sql`
- `applied/0103_reaction_notification_actor.sql`
- `applied/0104_backfill_reaction_notification_actors.sql`
- `applied/0116_feed_expires_at.sql`
- `applied/0118_comment_mentions.sql`
- `applied/0119_fix_appeal_blocked_by_owner_guard.sql`
- `applied/0135_get_feed_scope_param.sql`

### XP / levels / leaderboard (12)

- `applied/0032_restrict_increment_xp.sql`
- `applied/0033_fix_expire_cron.sql`
- `applied/0054_fix_double_xp_idempotency.sql`
- `applied/0057_schedule_expire_cron.sql`
- `applied/0062_fix_leaderboard_include_zero_xp.sql`
- `applied/0063_re_revoke_increment_xp.sql`
- `applied/0064_fix_xp_stats_rank.sql`
- `applied/0066_revoke_expire_from_users.sql`
- `applied/0110_revoke_xp_on_post_deletion.sql`
- `applied/0113_fix_xp_awarded_persist_and_recompute.sql`
- `applied/0132_compute_level_helper.sql`
- `applied/0141_gdpr_export.sql`

### Notifications & push (FCM) (17)

- `applied/0006_notifications.sql`
- `applied/0013_notifications_admin_insert.sql`
- `applied/0016_notification_announcement_type.sql`
- `applied/0022_notifications_insert_policy.sql`
- `applied/0029_restrict_fcm_token.sql`
- `applied/0030_upsert_fcm_token_rpc.sql`
- `applied/0035_get_fcm_token_rpc.sql`
- `applied/0036_new_notification_types.sql`
- `applied/0050_auto_push_on_notification_insert.sql`
- `applied/0051_fix_appeal_notification_trigger.sql`
- `applied/0070_drop_duplicate_push_trigger.sql`
- `applied/0080_get_all_fcm_tokens_rpc.sql`
- `applied/0095_delete_own_fcm_token.sql`
- `applied/0101_notification_actor_id.sql`
- `applied/0111_admin_removal_notification_copy.sql`
- `applied/0131_notification_body_cap.sql`
- `applied/0137_notification_copy_refresh.sql`

### Telegram moderation bot (2)

- `applied/0106_telegram_command_state.sql`
- `applied/0107_telegram_daily_summary_cron.sql`

### Admin & moderation (12)

- `applied/0007_admins.sql`
- `applied/0012_fix_reviewed_by_fk.sql`
- `applied/0038_admin_pending_review_reminder.sql`
- `applied/0040_seed_admin_user.sql`
- `applied/0048_appeal_support.sql`
- `applied/0061_revoke_admin_rpcs.sql`
- `applied/0067_announcement_persistence.sql`
- `applied/0069_content_moderation.sql`
- `applied/0098_admin_audit_log.sql`
- `applied/0099_admin_input_validation.sql`
- `applied/0100_admin_approve_with_note.sql`
- `applied/0121_audited_admin_writes.sql`

### Auth / account status / deletion (7)

- `applied/0011_storage.sql`
- `applied/0068_user_account_status.sql`
- `applied/0091_delete_own_account.sql`
- `applied/0122_account_deletion_queue.sql`
- `applied/0123_banned_user_write_guard.sql`
- `applied/0128_cron_drain_account_deletions.sql`
- `applied/0142_age_gate_and_consent.sql`

### Security audits & RLS hardening (7)

- `applied/0009_rls_policies.sql`
- `applied/0027_security_fixes.sql`
- `applied/0120_security_hardening.sql`
- `applied/0126_daily_summary_secret_header.sql`
- `applied/0140_security_audit_2026_05_17.sql`
- `applied/0143_emergency_pentest_lockdown.sql`
- `applied/0145_realtime_with_rls_filter.sql`

### Config / cron / infra (5)

- `applied/0017_add_mixed_media_type.sql`
- `applied/0084_app_config.sql`
- `applied/0108_maintenance_mode.sql`
- `applied/0127_fix_media_url_validation.sql`
- `applied/0130_dynamic_project_url.sql`

### Other (14)

- `applied/0008_indexes.sql`
- `applied/0010_rpc_functions.sql`
- `applied/0028_fix_fk_consistency.sql`
- `applied/0031_notify_rpc.sql`
- `applied/0039_update_notify_allowlist.sql`
- `applied/0045_allow_generate_while_submitted.sql`
- `applied/0079_injection_return_shape_and_no_notif.sql`
- `applied/0086_vote_system_and_saved_posts.sql`
- `applied/0112_inject_fixes.sql`
- `applied/0114_user_self_delete_and_deleted_posts_view.sql`
- `applied/0117_get_user_saved_posts_rpc.sql`
- `applied/0124_reroll_cooldown.sql`
- `applied/0133_owner_writable_columns_table.sql`
- `applied/0136_enable_realtime_for_realtime_sweep.sql`
