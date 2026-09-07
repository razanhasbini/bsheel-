CREATE TABLE telegram_command_state (
  chat_id bigint PRIMARY KEY,
  command text NOT NULL,
  step text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE telegram_webhook_updates (
  update_id bigint PRIMARY KEY,
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'processed', 'failed')),
  locked_until timestamptz NOT NULL DEFAULT now() + interval '2 minutes',
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts > 0),
  last_error text,
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX telegram_webhook_updates_retention_idx
  ON telegram_webhook_updates (processed_at)
  WHERE status = 'processed';

COMMENT ON TABLE telegram_command_state IS
  'Per-chat state for multi-step Telegram administrator commands.';
COMMENT ON TABLE telegram_webhook_updates IS
  'Idempotency and retry state for Telegram webhook updates.';
