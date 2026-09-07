CREATE TABLE auth_action_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose text NOT NULL CHECK (purpose IN ('password_recovery', 'email_confirmation')),
  token_hash bytea NOT NULL UNIQUE,
  encrypted_token bytea NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX auth_action_tokens_pending_user_idx
  ON auth_action_tokens (user_id, purpose, expires_at)
  WHERE consumed_at IS NULL;
