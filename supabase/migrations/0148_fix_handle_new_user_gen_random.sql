-- ============================================================
-- MIGRATION 0148: Fix signup — handle_new_user() used pgcrypto's
-- gen_random_bytes(), which self-hosted Postgres exposes only in the
-- `extensions` schema. The SECURITY DEFINER trigger ran without that
-- schema on its search_path, so EVERY signup failed with:
--   ERROR: function gen_random_bytes(integer) does not exist (42883)
--   -> GoTrue: "Database error saving new user" (500)
-- (Hosted Supabase preinstalls pgcrypto on the default search_path, so
--  this only surfaced after the self-host migration.)
--
-- Fix: build the fallback username from core `gen_random_uuid()` (always
-- in pg_catalog, no extension needed) instead of gen_random_bytes(), and
-- pin an explicit search_path on the SECURITY DEFINER function (best
-- practice — stops search_path hijacking of a definer-rights function).
-- Behaviour is otherwise identical to the 0142 version; idempotent.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_raw_username     text;
  v_clean_username   text;
  v_display_name     text;
  v_age_verified     boolean;
BEGIN
  v_raw_username := new.raw_user_meta_data ->> 'username';
  v_display_name := coalesce(
    new.raw_user_meta_data ->> 'display_name',
    'New User'
  );
  v_age_verified := coalesce(
    (new.raw_user_meta_data ->> 'age_verified')::boolean,
    false
  );

  v_clean_username := regexp_replace(coalesce(v_raw_username, ''), '[^A-Za-z0-9_]', '', 'g');
  IF length(v_clean_username) < 3 THEN
    -- Core gen_random_uuid() (pg_catalog) — no pgcrypto dependency.
    v_clean_username := 'user_' ||
      substring(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  ELSIF length(v_clean_username) > 30 THEN
    v_clean_username := substring(v_clean_username, 1, 30);
  END IF;

  v_display_name := nullif(btrim(v_display_name), '');
  IF v_display_name IS NULL THEN v_display_name := v_clean_username; END IF;
  IF length(v_display_name) > 100 THEN
    v_display_name := substring(v_display_name, 1, 100);
  END IF;

  INSERT INTO public.profiles (id, username, display_name, age_verified)
    VALUES (new.id, v_clean_username, v_display_name, v_age_verified)
    ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;
