-- ============================================================
-- MIGRATION 0141: GDPR / CCPA data export (M18, 2026-05-17 audit)
--
-- Users have a legal right (GDPR Article 20, CCPA §1798.110) to a
-- machine-readable copy of all data the app holds about them. Before
-- this migration there was no way to fulfil such a request without
-- a manual service-role dump.
--
-- This migration adds a single SECURITY DEFINER RPC,
-- `export_my_data()`, that returns a jsonb document containing:
--   - profile
--   - active and historical user_quests
--   - submissions (own)
--   - comments authored
--   - reactions left
--   - follows (both directions)
--   - notifications received
--
-- The RPC is rate-limited via the same general-purpose audit-log
-- pattern: a row in `gdpr_export_log` tracks requests so a user
-- can't trigger the export 1000 times per minute. One export per
-- 5 minutes per user is plenty for legitimate use.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.gdpr_export_log (
  id           bigserial PRIMARY KEY,
  user_id      uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gdpr_export_log_user_time
  ON public.gdpr_export_log (user_id, requested_at DESC);

ALTER TABLE public.gdpr_export_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gdpr_export_log_select_own ON public.gdpr_export_log;
CREATE POLICY gdpr_export_log_select_own ON public.gdpr_export_log
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_used      integer;
  v_window    interval := interval '5 minutes';
  v_max       integer := 1;
  v_result    jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Rate-limit: 1 export per 5 minutes per user.
  SELECT count(*) INTO v_used
    FROM public.gdpr_export_log
    WHERE user_id = v_uid AND requested_at > now() - v_window;
  IF v_used >= v_max THEN
    RAISE EXCEPTION 'Export rate limit (try again in 5 minutes)'
      USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO public.gdpr_export_log (user_id) VALUES (v_uid);

  -- Build the export payload. Tables that don't exist yet in fresh
  -- databases get a NULL coalesced to '[]' to keep the shape stable.
  v_result := jsonb_build_object(
    'export_version', '1',
    'exported_at',    to_jsonb(now()),
    'user_id',        to_jsonb(v_uid),
    'profile', (
      SELECT to_jsonb(p) FROM public.profiles p WHERE p.id = v_uid
    ),
    'user_quests', coalesce((
      SELECT jsonb_agg(to_jsonb(uq))
        FROM public.user_quests uq
        WHERE uq.user_id = v_uid
    ), '[]'::jsonb),
    'submissions', coalesce((
      SELECT jsonb_agg(to_jsonb(s))
        FROM public.submissions s
        WHERE s.user_id = v_uid
    ), '[]'::jsonb),
    'comments', coalesce((
      SELECT jsonb_agg(to_jsonb(c))
        FROM public.comments c
        WHERE c.user_id = v_uid
    ), '[]'::jsonb),
    'reactions', coalesce((
      SELECT jsonb_agg(to_jsonb(r))
        FROM public.reactions r
        WHERE r.user_id = v_uid
    ), '[]'::jsonb),
    'follows_following', coalesce((
      SELECT jsonb_agg(to_jsonb(f))
        FROM public.follows f
        WHERE f.follower_id = v_uid
    ), '[]'::jsonb),
    'follows_followers', coalesce((
      SELECT jsonb_agg(to_jsonb(f))
        FROM public.follows f
        WHERE f.following_id = v_uid
    ), '[]'::jsonb),
    'notifications', coalesce((
      SELECT jsonb_agg(to_jsonb(n))
        FROM public.notifications n
        WHERE n.user_id = v_uid
    ), '[]'::jsonb)
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.export_my_data() TO authenticated;

COMMENT ON FUNCTION public.export_my_data() IS
  'M18 (2026-05-17): GDPR Article 20 / CCPA data export. One call per 5min per user.';
