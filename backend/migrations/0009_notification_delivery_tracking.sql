CREATE TABLE notification_deliveries (
  notification_id uuid NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  device_token_id uuid NOT NULL REFERENCES device_tokens(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'invalid')),
  attempts integer NOT NULL DEFAULT 0,
  fcm_message_name text,
  last_error text,
  delivered_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (notification_id, device_token_id)
);

CREATE INDEX notification_deliveries_pending_idx
  ON notification_deliveries (notification_id, status)
  WHERE status = 'pending';
