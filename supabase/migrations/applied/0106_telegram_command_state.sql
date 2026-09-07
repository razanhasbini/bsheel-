-- ============================================================
-- MIGRATION 0106: Telegram per-chat command state
-- Stores in-progress multi-step commands (e.g. /quest add) keyed
-- by Telegram chat_id. Telegram itself is stateless, so we keep
-- the FSM here.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.telegram_command_state (
  chat_id    bigint      PRIMARY KEY,
  command    text        NOT NULL,
  step       text        NOT NULL,
  data       jsonb       NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Service role only — this is admin/webhook-only data, no end users
-- ever touch it. Block PostgREST entirely.
ALTER TABLE public.telegram_command_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.telegram_command_state FROM anon, authenticated;

COMMENT ON TABLE public.telegram_command_state IS
  'Per-chat FSM state for multi-step Telegram bot commands (e.g. /quest add).';
