-- ============================================================
-- MIGRATION 0142: Age gate + analytics consent + audit-log integrity
-- (Low/Info batch from 2026-05-17 audit)
--
-- 1. age_verified  — required true at signup, lets us prove compliance
--    with COPPA / GDPR-K / Saudi PDPL minor protections. UI needs a
--    "I confirm I am 13 or older" checkbox in signup_page.
-- 2. analytics_consent_at — null = not yet consented; set when the
--    user accepts the analytics opt-in dialog. AnalyticsService.init()
--    should check this before initializing Mixpanel.
-- 3. admin_audit_log gets a deny-on-update / deny-on-delete RLS pair
--    so even a super_admin can't tamper with the audit chain.
--
-- All idempotent.
-- ============================================================

-- ── 1. age_verified ─────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS age_verified boolean NOT NULL DEFAULT false;

-- ── 2. analytics_consent_at ─────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS analytics_consent_at timestamptz;

COMMENT ON COLUMN public.profiles.age_verified IS
  'M18-LOW (2026-05-17): user confirmed they are 13+ at signup. UI checkbox required before submit.';
COMMENT ON COLUMN public.profiles.analytics_consent_at IS
  'M18-LOW (2026-05-17): timestamp the user accepted analytics opt-in. NULL = no consent yet; do not call Mixpanel until set.';

-- ── 3. handle_new_user copies age_verified from signup metadata ─
-- Patches the 0120 version so the signup-page checkbox value lands
-- on profiles.age_verified. Default stays false if metadata absent
-- (e.g. admin-created accounts via admin_manage_user).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
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
    v_clean_username := 'user_' ||
      substring(encode(gen_random_bytes(4), 'hex'), 1, 8);
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 4. admin_audit_log immutability ─────────────────────────────
-- The audit log lives in 0098 with append-by-admin / read-by-super.
-- Add explicit DROP-then-DENY policies for UPDATE and DELETE so even
-- a super_admin connecting via the standard authenticated role can't
-- rewrite history. Service-role DDL still works (Supabase functions
-- using SUPABASE_SERVICE_ROLE_KEY); the intent is to block the
-- "compromised admin covers their tracks" scenario.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'admin_audit_log'
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS admin_audit_log_no_update ON public.admin_audit_log';
    EXECUTE 'DROP POLICY IF EXISTS admin_audit_log_no_delete ON public.admin_audit_log';
    EXECUTE 'CREATE POLICY admin_audit_log_no_update ON public.admin_audit_log FOR UPDATE TO authenticated USING (false) WITH CHECK (false)';
    EXECUTE 'CREATE POLICY admin_audit_log_no_delete ON public.admin_audit_log FOR DELETE TO authenticated USING (false)';
  END IF;
END $$;
