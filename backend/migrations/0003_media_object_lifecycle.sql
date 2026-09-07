CREATE TYPE media_object_kind AS ENUM ('avatar', 'submission');
CREATE TYPE media_object_status AS ENUM ('pending', 'ready', 'rejected', 'deleted');

CREATE TABLE media_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id uuid NOT NULL,
  object_key text NOT NULL UNIQUE CHECK (char_length(object_key) BETWEEN 1 AND 500),
  kind media_object_kind NOT NULL,
  status media_object_status NOT NULL DEFAULT 'pending',
  content_type text NOT NULL,
  declared_size_bytes bigint NOT NULL CHECK (declared_size_bytes > 0),
  stored_size_bytes bigint CHECK (stored_size_bytes > 0),
  etag text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  deleted_at timestamptz,
  UNIQUE (user_id, client_request_id)
);

CREATE INDEX media_objects_user_created_idx ON media_objects (user_id, created_at DESC);
CREATE INDEX media_objects_pending_idx ON media_objects (created_at)
  WHERE status = 'pending';
