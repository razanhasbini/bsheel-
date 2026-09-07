-- ============================================================
-- MIGRATION 0145: Re-add submissions/reactions to supabase_realtime
--
-- Migration 0143 (emergency pentest lockdown) removed ALL social
-- tables from the supabase_realtime publication to close the
-- anonymous WebSocket exfiltration vector reported in F-005.
-- That worked but it also took out the client-side feed realtime
-- (feedRealtimeProvider) — users no longer see new posts pop in,
-- have to pull-to-refresh.
--
-- Now that 0143's RLS policies are in place and verified blocking
-- all anonymous reads on profiles/submissions/reactions/comments/
-- follows, we can re-add submissions and reactions to the
-- publication SAFELY. Postgres logical CDC respects RLS at
-- delivery time — an anon subscription will still receive zero
-- events for these tables because the SELECT policy denies them.
--
-- We DO NOT re-add profiles/comments/follows. Those tables drive
-- visible UI in ways the client already handles via explicit
-- invalidation on user action, and keeping them out of the
-- publication shrinks the attack surface further.
--
-- Idempotent: each ADD TABLE is wrapped in a NOT-EXISTS check
-- against pg_publication_tables.
-- ============================================================

DO $$
BEGIN
  -- submissions: drives feedRealtimeProvider (new posts pop in,
  -- moderation-state flips update visible posts). RLS policy from
  -- 0143 (`submissions_select_approved_authenticated`) restricts
  -- to status='approved' AND visibility='visible' AND auth.uid()
  -- IS NOT NULL — so anon gets nothing, authed users only see
  -- events for posts they could have read anyway.
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'submissions'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.submissions';
  END IF;

  -- reactions: drives the optimistic-vote rollback path + the
  -- post-detail counts. RLS from 0143
  -- (`reactions_select_authenticated`) restricts to auth.uid() IS
  -- NOT NULL — same anon-blocked posture.
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'reactions'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.reactions';
  END IF;

  -- INTENTIONALLY NOT RE-ADDED:
  --   profiles  — change events leak presence/online behaviour
  --               and aren't needed by the feed (we invalidate
  --               profile providers on explicit user action).
  --   comments  — same reasoning; commentsProvider invalidates
  --               via post_realtime_provider when a parent
  --               submission row changes.
  --   follows   — social-graph events. The follow button does its
  --               own invalidation on tap; nothing else needs
  --               realtime here.
END $$;

COMMENT ON PUBLICATION supabase_realtime IS
  'Realtime CDC publication. submissions+reactions re-added in 0145 — RLS from 0143 filters anon. profiles/comments/follows intentionally excluded.';
