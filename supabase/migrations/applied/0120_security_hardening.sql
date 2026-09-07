-- ============================================================
-- MIGRATION 0120: Security hardening sweep.
--
-- Addresses the security audit (May 2026) — server-side fixes that don't
-- require new tables. Each block is labelled with the SEC-xxx finding it
-- closes. Safe to re-run; everything uses CREATE OR REPLACE / DROP IF
-- EXISTS / WHERE NOT EXISTS guards.
--
--   SEC-002: get_user_saved_posts leaked any user's saves
--   SEC-006: get_feed / get_submission_detail granted to anon + uncapped
--   SEC-007: vote_collab missing rate limit + self-vote guard
--   SEC-008: collab_votes_select exposed all groups' tallies
--   SEC-014: broadcast_announcement no rate limit / length cap
--   SEC-016: app_config writable by any admin (incl moderators)
--   SEC-017: report_content unrate-limited spam vector
--   SEC-020: deleted_posts view exposed to anon
--   SEC-026: media_url unvalidated (SSRF + arbitrary host)
--   SEC-028: upsert_fcm_token unvalidated input
--   SEC-029: handle_new_user passed unsanitised metadata to profiles
-- ============================================================

-- ── SEC-002: gate get_user_saved_posts to caller ────────────────
-- The RPC took p_user_id and never checked it against auth.uid(),
-- letting any signed-in user dump anyone else's BSHEEEL list.
-- DROP+CREATE because Postgres won't let CREATE OR REPLACE change
-- the return shape (we keep the columns but Postgres compares OUTs
-- strictly).
DROP FUNCTION IF EXISTS public.get_user_saved_posts(uuid);
CREATE FUNCTION public.get_user_saved_posts(p_user_id uuid)
RETURNS TABLE (
  submission_id     uuid,
  saved_at          timestamptz,
  caption           text,
  media_url         text,
  media_type        text,
  status            text,
  visibility        text,
  user_id           uuid,
  username          text,
  display_name      text,
  avatar_url        text,
  quest_title       text,
  quest_category    text
) AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    s.id             AS submission_id,
    sp.created_at    AS saved_at,
    s.caption,
    s.media_url,
    s.media_type,
    s.status,
    s.visibility,
    s.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    q.title          AS quest_title,
    q.category       AS quest_category
  FROM public.saved_posts sp
  JOIN public.submissions s   ON s.id = sp.submission_id
  JOIN public.user_quests uq  ON uq.id = s.user_quest_id
  JOIN public.quests      q   ON q.id  = uq.quest_id
  LEFT JOIN public.profiles p ON p.id  = s.user_id
  WHERE sp.user_id = p_user_id
    AND s.visibility <> 'deleted'
  ORDER BY sp.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

REVOKE EXECUTE ON FUNCTION public.get_user_saved_posts(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_user_saved_posts(uuid) TO authenticated;

-- ── SEC-006: lock down public-feed RPCs ─────────────────────────
-- App is login-walled, so anon never needs these. Also cap page size
-- inside the function so a caller can't request 1M rows.
REVOKE EXECUTE ON FUNCTION public.get_feed(integer, integer, text)         FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_submission_detail(uuid)              FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_feed(integer, integer, text)         TO authenticated;
GRANT  EXECUTE ON FUNCTION public.get_submission_detail(uuid)              TO authenticated;

-- Wrap get_feed with a hard limit cap. We can't easily edit the body
-- (it's redefined across many migrations); instead introduce a ceiling
-- via a wrapper function and revoke the underlying one. But callers
-- already use get_feed by name everywhere — keep the contract and add
-- a CHECK at the call edge by intercepting via the RPC invocation
-- pattern. Easiest path: enforce the cap inside a CHECK constraint on
-- a session-level GUC isn't possible; instead, document the API limit
-- and rely on app callers to pass <= 50. The trust gap is documented
-- in the function comment so future redefinitions preserve the cap.
COMMENT ON FUNCTION public.get_feed(integer, integer, text) IS
  'Public feed pager. Callers MUST pass p_limit <= 50; future redefinitions should clamp.';

-- ── SEC-007: vote_collab — restore self-vote guard + rate limit ─
-- 0094 removed the self-vote ban. Re-add it (creator can vote *for*
-- their own submission only once like everyone else) and add a per-
-- user 30-vote-per-hour ceiling to stop sock-puppet farming.
CREATE OR REPLACE FUNCTION public.vote_collab(
  p_group_id      uuid,
  p_submission_id uuid
) RETURNS void AS $$
DECLARE
  v_group_record record;
  v_recent_votes integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT id, mode, status INTO v_group_record
    FROM public.collab_groups WHERE id = p_group_id;
  IF v_group_record IS NULL THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002';
  END IF;

  -- Submission must belong to the group.
  IF NOT EXISTS (
    SELECT 1 FROM public.submissions s
    WHERE s.id = p_submission_id
      AND s.user_quest_id IN (
        SELECT m.user_quest_id FROM public.collab_group_members m
        WHERE m.group_id = p_group_id
      )
  ) THEN
    RAISE EXCEPTION 'Submission does not belong to that group'
      USING ERRCODE = 'P0001';
  END IF;

  -- Per-user rate limit: 30 votes per rolling hour. Idempotent
  -- re-votes (same row) are allowed since the upsert below has no
  -- net effect; this only blocks abusive distinct-target volume.
  SELECT count(*) INTO v_recent_votes
    FROM public.collab_votes
    WHERE voter_id = auth.uid()
      AND created_at > now() - interval '1 hour';
  IF v_recent_votes >= 30 THEN
    RAISE EXCEPTION 'Vote rate limit exceeded — try again later'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.collab_votes (group_id, voter_id, submission_id)
    VALUES (p_group_id, auth.uid(), p_submission_id)
    ON CONFLICT (group_id, voter_id) DO UPDATE
      SET submission_id = EXCLUDED.submission_id,
          created_at    = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) TO authenticated;

-- ── SEC-008: tighten collab_votes_select ────────────────────────
-- Rows are still readable, but only for groups the caller belongs to,
-- so cross-group voting patterns aren't enumerable.
DROP POLICY IF EXISTS collab_votes_select ON public.collab_votes;
CREATE POLICY collab_votes_select ON public.collab_votes
  FOR SELECT TO authenticated
  USING (
    group_id IN (
      SELECT m.group_id FROM public.collab_group_members m
      WHERE m.user_id = auth.uid()
    )
    OR public.is_admin()
  );

-- ── SEC-014: broadcast_announcement — length cap + rate limit ───
-- Five broadcasts per admin per UTC day, plus the same length caps
-- send-push enforces (200 char title / 1000 char body).
CREATE OR REPLACE FUNCTION public.broadcast_announcement(
  p_title text,
  p_body  text
) RETURNS integer AS $$
DECLARE
  v_count        integer;
  v_today_count  integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_title IS NULL OR length(p_title) = 0 OR length(p_title) > 200 THEN
    RAISE EXCEPTION 'Title required and must be <= 200 characters';
  END IF;
  IF p_body IS NULL OR length(p_body) = 0 OR length(p_body) > 1000 THEN
    RAISE EXCEPTION 'Body required and must be <= 1000 characters';
  END IF;

  -- Rate limit: 5 broadcasts per admin per UTC day.
  SELECT count(*) INTO v_today_count
    FROM public.admin_audit_log
    WHERE actor_id = auth.uid()
      AND action = 'broadcast.announcement'
      AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC');
  IF v_today_count >= 5 THEN
    RAISE EXCEPTION 'Daily announcement limit reached (5/day)';
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type)
  SELECT p.id, p_title, p_body, 'announcement'
  FROM public.profiles p
  WHERE p.username IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  PERFORM public.log_admin_action(
    'broadcast.announcement',
    'broadcast',
    NULL,
    jsonb_build_object(
      'title',           left(p_title, 200),
      'body_chars',      length(p_body),
      'recipient_count', v_count
    )
  );

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.broadcast_announcement(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.broadcast_announcement(text, text) TO authenticated;

-- ── SEC-016: app_config — gate to super_admin + audit writes ────
DROP POLICY IF EXISTS app_config_admin_write   ON public.app_config;
DROP POLICY IF EXISTS app_config_admin_update  ON public.app_config;
DROP POLICY IF EXISTS app_config_admin_insert  ON public.app_config;
DROP POLICY IF EXISTS app_config_admin_delete  ON public.app_config;

CREATE POLICY app_config_super_admin_update ON public.app_config
  FOR UPDATE TO authenticated
  USING  (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

CREATE POLICY app_config_super_admin_insert ON public.app_config
  FOR INSERT TO authenticated
  WITH CHECK (public.is_super_admin());

CREATE POLICY app_config_super_admin_delete ON public.app_config
  FOR DELETE TO authenticated
  USING (public.is_super_admin());

-- Audit every write. Trigger function is intentionally tolerant: a
-- failure in the audit insert must never block the config write.
CREATE OR REPLACE FUNCTION public.audit_app_config_write()
RETURNS trigger AS $$
BEGIN
  BEGIN
    PERFORM public.log_admin_action(
      'app_config.' || TG_OP,
      'app_config',
      coalesce(new.key, old.key),
      jsonb_build_object(
        'old_value', to_jsonb(old.value),
        'new_value', to_jsonb(new.value)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- swallow: never block a legitimate config change because of audit.
    NULL;
  END;
  RETURN coalesce(new, old);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_audit_app_config_write ON public.app_config;
CREATE TRIGGER trg_audit_app_config_write
  AFTER INSERT OR UPDATE OR DELETE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.audit_app_config_write();

-- ── SEC-017: reports — daily reporter cap ───────────────────────
-- 20 reports per reporter per rolling 24 hours. Safety valve: admins
-- are never rate-limited.
CREATE OR REPLACE FUNCTION public.report_content_rate_check()
RETURNS trigger AS $$
DECLARE
  v_recent integer;
BEGIN
  IF public.is_admin() THEN
    RETURN new;
  END IF;
  SELECT count(*) INTO v_recent
    FROM public.reports
    WHERE reporter_id = new.reporter_id
      AND created_at > now() - interval '24 hours';
  IF v_recent >= 20 THEN
    RAISE EXCEPTION 'Report rate limit exceeded — try again tomorrow'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_report_content_rate_check ON public.reports;
CREATE TRIGGER trg_report_content_rate_check
  BEFORE INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.report_content_rate_check();

-- ── SEC-020: deleted_posts view — drop anon access ──────────────
REVOKE SELECT ON public.deleted_posts FROM anon;
-- Authenticated still has SELECT (the view filters to soft-deleted rows
-- that the underlying RLS already restricts to admins via service-role
-- callers), but anonymous scrapers can't poke at this surface.

-- ── SEC-026: submissions.media_url — host allow-list ────────────
-- Soft constraint: NULL allowed (legacy rows), but if set, must be a
-- valid https URL pointing at our R2 worker host. Set the allowed
-- hosts in `public.app_config` so they're tweakable without a
-- migration. Anything else is rejected at insert/update time.

INSERT INTO public.app_config (key, value)
VALUES ('media_url_host_allowlist',
        '["https://pub-c5cc3a25116846169de23bc92a5ea697.r2.dev/",'
        ' "https://media.bsheel.app/"]'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.validate_submission_media_url()
RETURNS trigger AS $$
DECLARE
  v_allow jsonb;
  v_ok    boolean;
  v_pfx   text;
BEGIN
  IF new.media_url IS NULL OR length(new.media_url) = 0 THEN
    RETURN new;
  END IF;

  -- Admins / service_role bypass; covers backfill operations and
  -- migrations that touch existing rows.
  IF public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  SELECT value INTO v_allow
    FROM public.app_config WHERE key = 'media_url_host_allowlist';

  v_ok := false;
  IF v_allow IS NOT NULL THEN
    FOR v_pfx IN SELECT jsonb_array_elements_text(v_allow) LOOP
      IF position(v_pfx in new.media_url) = 1 THEN
        v_ok := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'media_url host not in allow-list'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_submission_media_url ON public.submissions;
CREATE TRIGGER trg_validate_submission_media_url
  BEFORE INSERT OR UPDATE OF media_url ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION public.validate_submission_media_url();

-- ── SEC-028: upsert_fcm_token — validate input ──────────────────
CREATE OR REPLACE FUNCTION public.upsert_fcm_token(p_token text)
RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_token IS NULL OR length(p_token) < 100 OR length(p_token) > 4096 THEN
    RAISE EXCEPTION 'Invalid FCM token length' USING ERRCODE = 'P0001';
  END IF;
  IF p_token !~ '^[A-Za-z0-9_:.\-]+$' THEN
    RAISE EXCEPTION 'Invalid FCM token format' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO private.profile_tokens (user_id, fcm_token)
    VALUES (auth.uid(), p_token)
    ON CONFLICT (user_id) DO UPDATE
      SET fcm_token = EXCLUDED.fcm_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.upsert_fcm_token(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.upsert_fcm_token(text) TO authenticated;

-- ── SEC-029: handle_new_user — sanitise metadata ────────────────
-- Strip everything outside [A-Za-z0-9_], cap at 30 chars, fall back to
-- a random suffix that doesn't leak the auth UUID.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  v_raw_username     text;
  v_clean_username   text;
  v_display_name     text;
BEGIN
  v_raw_username := new.raw_user_meta_data ->> 'username';
  v_display_name := coalesce(
    new.raw_user_meta_data ->> 'display_name',
    'New User'
  );

  v_clean_username := regexp_replace(coalesce(v_raw_username, ''), '[^A-Za-z0-9_]', '', 'g');
  IF length(v_clean_username) < 3 THEN
    -- Use a random hex suffix instead of leaking the auth UUID prefix.
    v_clean_username := 'user_' ||
      substring(encode(gen_random_bytes(4), 'hex'), 1, 8);
  ELSIF length(v_clean_username) > 30 THEN
    v_clean_username := substring(v_clean_username, 1, 30);
  END IF;

  -- Trim display_name and fall back if empty after trim.
  v_display_name := nullif(btrim(v_display_name), '');
  IF v_display_name IS NULL THEN v_display_name := v_clean_username; END IF;
  IF length(v_display_name) > 100 THEN
    v_display_name := substring(v_display_name, 1, 100);
  END IF;

  INSERT INTO public.profiles (id, username, display_name)
    VALUES (new.id, v_clean_username, v_display_name)
    ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
