-- Admin bootstrap (self-hosted GoTrue) — run by scripts/server-deploy.sh.
--
-- Creates (or rotates) a super_admin account directly in the auth stack.
-- NO credential lives in this file: the password arrives at runtime as the
-- psql variable :admin_pw (server-deploy.sh passes it from the
-- NEW_ADMIN_PASSWORD env / GitHub secret). If it's empty, this is a no-op.
--
-- Idempotent:
--   * user absent → create GoTrue user (email-confirmed) + identity + profile
--   * user present → rotate password + ensure super_admin role
--
-- Usage (server-side):
--   psql -v admin_email=... -v admin_username=... -v admin_pw=... < admin_bootstrap.sql

SELECT set_config('bsheel.admin_email', :'admin_email', false);
SELECT set_config('bsheel.admin_username', :'admin_username', false);
SELECT set_config('bsheel.admin_pw', :'admin_pw', false);

DO $bootstrap$
DECLARE
  v_email    text := lower(trim(coalesce(current_setting('bsheel.admin_email', true), '')));
  v_username text := coalesce(nullif(trim(current_setting('bsheel.admin_username', true)), ''), 'admin');
  v_pw       text := coalesce(current_setting('bsheel.admin_pw', true), '');
  v_uid      uuid;
  v_has_provider_id boolean;
BEGIN
  IF v_pw = '' OR v_email = '' THEN
    RAISE NOTICE '[admin-bootstrap] no email/password provided — skipping';
    RETURN;
  END IF;

  SELECT id INTO v_uid FROM auth.users WHERE email = v_email;

  IF v_uid IS NULL THEN
    v_uid := gen_random_uuid();

    -- Empty-string (not NULL) token columns: some GoTrue versions error on
    -- NULL here ("converting NULL to string is unsupported").
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
      v_email, crypt(v_pw, gen_salt('bf', 10)),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('username', v_username, 'display_name', v_username),
      '', '', '', ''
    );

    -- Identity row — schema differs across GoTrue versions (provider_id
    -- added in newer builds). Insert defensively.
    SELECT EXISTS(
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'auth' AND table_name = 'identities'
        AND column_name = 'provider_id'
    ) INTO v_has_provider_id;

    IF v_has_provider_id THEN
      INSERT INTO auth.identities
        (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      VALUES
        (gen_random_uuid(), v_uid::text, v_uid,
         jsonb_build_object('sub', v_uid::text, 'email', v_email),
         'email', now(), now(), now());
    ELSE
      INSERT INTO auth.identities
        (id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      VALUES
        (gen_random_uuid(), v_uid,
         jsonb_build_object('sub', v_uid::text, 'email', v_email),
         'email', now(), now(), now());
    END IF;

    RAISE NOTICE '[admin-bootstrap] created auth user % (%)', v_email, v_uid;
  ELSE
    -- Rotate the password so updating the secret + redeploying changes it.
    UPDATE auth.users
       SET encrypted_password = crypt(v_pw, gen_salt('bf', 10)),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     WHERE id = v_uid;
    RAISE NOTICE '[admin-bootstrap] user % exists — password rotated', v_email;
  END IF;

  -- Profile is normally created by the handle_new_user trigger; ensure it.
  INSERT INTO public.profiles (id, username, display_name)
  VALUES (v_uid, v_username, v_username)
  ON CONFLICT (id) DO NOTHING;

  -- Grant / confirm super_admin.
  INSERT INTO public.admins (user_id, role)
  VALUES (v_uid, 'super_admin')
  ON CONFLICT (user_id) DO UPDATE SET role = 'super_admin';

  RAISE NOTICE '[admin-bootstrap] % is super_admin', v_email;
END
$bootstrap$;
