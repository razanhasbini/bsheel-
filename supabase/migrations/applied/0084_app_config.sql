-- ============================================================
-- MIGRATION 0084: App config key-value table
--
-- Simple feature flags / app config managed by super admins.
-- Readable by all authenticated users, writable only by admins.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.app_config (
  key   text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Seed the social login toggle (enabled by default)
INSERT INTO public.app_config (key, value)
VALUES ('social_login_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

-- RLS: anyone can read, only service_role/admins can write
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read app_config"
  ON public.app_config FOR SELECT
  USING (true);

CREATE POLICY "Only admins can update app_config"
  ON public.app_config FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));

CREATE POLICY "Only admins can insert app_config"
  ON public.app_config FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));
