-- ============================================================
-- MIGRATION 0127: Hotfix for 0120's validate_submission_media_url.
--
-- The trigger added in 0120 used `position(prefix in url) = 1`, which
-- expects a bare URL. In production, `submissions.media_url` is a
-- JSON-encoded array of URL strings (one entry per attachment), e.g.
--   ["https://pub-c5cc3a25116846169de23bc92a5ea697.r2.dev/.../1.jpg",
--    "https://pub-c5cc3a25116846169de23bc92a5ea697.r2.dev/.../2.mp4"]
-- so position-1 never matched and every new submission would be
-- rejected with `media_url host not in allow-list`.
--
-- This relaxes to "contains" matching against the same allow-list,
-- and adds a fail-open path when the allow-list is missing/empty so
-- a future config wipe can never block prod submissions silently.
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_submission_media_url()
RETURNS trigger AS $$
DECLARE
  v_allow jsonb;
  v_pfx   text;
  v_pfx_count int := 0;
  v_match int := 0;
BEGIN
  IF new.media_url IS NULL OR length(new.media_url) = 0 THEN
    RETURN new;
  END IF;
  IF public.is_admin() OR pg_trigger_depth() > 1 THEN
    RETURN new;
  END IF;

  SELECT value INTO v_allow
    FROM public.app_config WHERE key = 'media_url_host_allowlist';
  IF v_allow IS NULL THEN
    RETURN new;
  END IF;

  FOR v_pfx IN SELECT jsonb_array_elements_text(v_allow) LOOP
    v_pfx_count := v_pfx_count + 1;
    IF position(v_pfx in new.media_url) > 0 THEN
      v_match := v_match + 1;
      EXIT;
    END IF;
  END LOOP;

  IF v_pfx_count = 0 THEN
    RETURN new;
  END IF;
  IF v_match = 0 THEN
    RAISE EXCEPTION 'media_url host not in allow-list'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql;
