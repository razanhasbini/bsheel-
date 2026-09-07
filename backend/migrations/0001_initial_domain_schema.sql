CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE account_status AS ENUM ('active', 'suspended', 'banned', 'deletion_pending');
CREATE TYPE admin_role AS ENUM ('moderator', 'admin', 'super_admin');
CREATE TYPE user_quest_status AS ENUM ('assigned', 'submitted', 'approved', 'rejected', 'expired', 'abandoned');
CREATE TYPE submission_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE submission_visibility AS ENUM ('visible', 'hidden', 'deleted');
CREATE TYPE media_type AS ENUM ('image', 'video', 'mixed');
CREATE TYPE reaction_type AS ENUM ('upvote', 'downvote');
CREATE TYPE collab_mode AS ENUM ('with', 'against');
CREATE TYPE collab_status AS ENUM ('open', 'active', 'completed', 'expired', 'abandoned');

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL UNIQUE,
  password_hash text,
  email_verified_at timestamptz,
  status account_status NOT NULL DEFAULT 'active',
  token_version integer NOT NULL DEFAULT 0 CHECK (token_version >= 0),
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT password_or_external_identity CHECK (password_hash IS NOT NULL OR email_verified_at IS NOT NULL)
);

CREATE TABLE auth_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('password', 'google', 'apple')),
  provider_subject text NOT NULL,
  provider_email citext,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_subject)
);

CREATE TABLE refresh_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  family_id uuid NOT NULL,
  user_agent text,
  ip_address inet,
  expires_at timestamptz NOT NULL,
  rotated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
  id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  username citext NOT NULL UNIQUE CHECK (char_length(username::text) BETWEEN 3 AND 30),
  display_name text NOT NULL DEFAULT '' CHECK (char_length(display_name) <= 80),
  avatar_url text,
  bio text CHECK (char_length(bio) <= 500),
  xp integer NOT NULL DEFAULT 0 CHECK (xp >= 0),
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1),
  quests_completed integer NOT NULL DEFAULT 0 CHECK (quests_completed >= 0),
  profile_completed boolean NOT NULL DEFAULT false,
  age_verified boolean NOT NULL DEFAULT false,
  analytics_consent_at timestamptz,
  accepted_terms_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE admins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  role admin_role NOT NULL DEFAULT 'moderator',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE quests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 2000),
  category text NOT NULL CHECK (char_length(category) BETWEEN 1 AND 80),
  difficulty text NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  xp_reward integer NOT NULL DEFAULT 10 CHECK (xp_reward BETWEEN 0 AND 10000),
  duration_hours integer NOT NULL DEFAULT 4 CHECK (duration_hours BETWEEN 1 AND 168),
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_quests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quest_id uuid NOT NULL REFERENCES quests(id) ON DELETE RESTRICT,
  status user_quest_status NOT NULL DEFAULT 'assigned',
  assigned_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  expires_at timestamptz NOT NULL,
  version integer NOT NULL DEFAULT 0,
  CHECK (expires_at > assigned_at)
);
CREATE UNIQUE INDEX user_quests_one_in_progress_idx
  ON user_quests (user_id) WHERE status IN ('assigned', 'submitted');
CREATE INDEX user_quests_user_history_idx ON user_quests (user_id, assigned_at DESC);
CREATE INDEX user_quests_expiration_idx ON user_quests (expires_at) WHERE status = 'assigned';

CREATE TABLE submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_quest_id uuid NOT NULL REFERENCES user_quests(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  media_url text NOT NULL CHECK (char_length(media_url) BETWEEN 1 AND 20000),
  media_type media_type NOT NULL DEFAULT 'image',
  caption text CHECK (char_length(caption) <= 2200),
  status submission_status NOT NULL DEFAULT 'pending',
  reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  review_note text CHECK (char_length(review_note) <= 2000),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  appeal_note text CHECK (char_length(appeal_note) <= 2000),
  appealed boolean NOT NULL DEFAULT false,
  show_in_feed boolean NOT NULL DEFAULT true,
  visibility submission_visibility NOT NULL DEFAULT 'visible',
  deleted_at timestamptz,
  xp_awarded boolean NOT NULL DEFAULT false,
  xp_awarded_amount integer NOT NULL DEFAULT 0 CHECK (xp_awarded_amount >= 0),
  telegram_message_id bigint,
  version integer NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX submissions_one_pending_per_quest_idx
  ON submissions (user_quest_id) WHERE status = 'pending';
CREATE INDEX submissions_feed_idx
  ON submissions (submitted_at DESC, id DESC)
  WHERE status = 'approved' AND show_in_feed AND visibility = 'visible' AND deleted_at IS NULL;
CREATE INDEX submissions_user_idx ON submissions (user_id, submitted_at DESC);
CREATE INDEX submissions_review_queue_idx ON submissions (status, submitted_at) WHERE status = 'pending';

CREATE TABLE reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type reaction_type NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (submission_id, user_id)
);
CREATE INDEX reactions_submission_type_idx ON reactions (submission_id, type);

CREATE TABLE comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  parent_id uuid REFERENCES comments(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_submission_created_idx ON comments (submission_id, created_at, id);
CREATE INDEX comments_parent_idx ON comments (parent_id) WHERE parent_id IS NOT NULL;

CREATE TABLE follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (follower_id <> following_id),
  UNIQUE (follower_id, following_id)
);
CREATE INDEX follows_following_idx ON follows (following_id, created_at DESC);

CREATE TABLE blocked_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (blocker_id <> blocked_id),
  UNIQUE (blocker_id, blocked_id)
);
CREATE INDEX blocked_users_reverse_idx ON blocked_users (blocked_id, blocker_id);

CREATE TABLE saved_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, submission_id)
);
CREATE INDEX saved_posts_user_created_idx ON saved_posts (user_id, created_at DESC);

CREATE TABLE saved_quests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quest_id uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, quest_id)
);
CREATE INDEX saved_quests_user_created_idx ON saved_quests (user_id, created_at DESC);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 180),
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
  type text NOT NULL CHECK (char_length(type) BETWEEN 1 AND 80),
  reference_id uuid,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_unread_idx ON notifications (user_id, created_at DESC) WHERE NOT is_read;
CREATE INDEX notifications_user_created_idx ON notifications (user_id, created_at DESC, id DESC);

CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  encrypted_token bytea NOT NULL,
  platform text NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_tokens_user_idx ON device_tokens (user_id);

CREATE TABLE collab_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quest_id uuid NOT NULL REFERENCES quests(id) ON DELETE RESTRICT,
  creator_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code citext NOT NULL UNIQUE CHECK (char_length(code::text) BETWEEN 4 AND 16),
  mode collab_mode NOT NULL DEFAULT 'with',
  status collab_status NOT NULL DEFAULT 'open',
  max_members integer NOT NULL DEFAULT 5 CHECK (max_members BETWEEN 2 AND 20),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX collab_groups_expiration_idx ON collab_groups (expires_at) WHERE status IN ('open', 'active');

CREATE TABLE collab_group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES collab_groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_quest_id uuid NOT NULL UNIQUE REFERENCES user_quests(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  submission_time_seconds integer CHECK (submission_time_seconds >= 0),
  UNIQUE (group_id, user_id)
);
CREATE INDEX collab_group_members_user_idx ON collab_group_members (user_id, joined_at DESC);

CREATE TABLE collab_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES collab_groups(id) ON DELETE CASCADE,
  voter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  submission_id uuid NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, voter_id)
);
CREATE INDEX collab_votes_submission_idx ON collab_votes (submission_id);

CREATE TABLE reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_type text NOT NULL CHECK (reported_type IN ('submission', 'comment', 'user')),
  reported_id text NOT NULL,
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 500),
  admin_note text CHECK (char_length(admin_note) <= 2000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed', 'actioned')),
  reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reporter_id, reported_type, reported_id)
);
CREATE INDEX reports_queue_idx ON reports (status, created_at) WHERE status = 'pending';

CREATE TABLE admin_quest_injections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quest_id uuid NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX admin_quest_injections_pending_idx ON admin_quest_injections (target_user_id) WHERE consumed_at IS NULL;

CREATE TABLE quest_of_the_day (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quest_id uuid NOT NULL REFERENCES quests(id) ON DELETE RESTRICT,
  display_date date NOT NULL UNIQUE,
  ticket_no text,
  bonus_xp integer NOT NULL DEFAULT 0 CHECK (bonus_xp BETWEEN 0 AND 10000),
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE quest_reroll_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_quest_id uuid REFERENCES user_quests(id) ON DELETE SET NULL,
  rerolled_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX quest_reroll_log_user_time_idx ON quest_reroll_log (user_id, rerolled_at DESC);

CREATE TABLE app_config (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  description text,
  is_public boolean NOT NULL DEFAULT false,
  updated_by uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  rollout_percentage integer NOT NULL DEFAULT 0 CHECK (rollout_percentage BETWEEN 0 AND 100),
  rules jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_by uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL UNIQUE,
  source text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE quest_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext,
  title text NOT NULL CHECK (char_length(title) BETWEEN 3 AND 160),
  description text CHECK (char_length(description) <= 2000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  reviewed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE account_delete_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  execute_after timestamptz NOT NULL,
  cancelled_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX account_delete_requests_due_idx ON account_delete_requests (execute_after) WHERE completed_at IS NULL AND cancelled_at IS NULL;

CREATE TABLE gdpr_export_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  object_key text,
  expires_at timestamptz
);

CREATE TABLE admin_audit_log (
  id bigserial PRIMARY KEY,
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_type text NOT NULL,
  target_id text,
  before_state jsonb,
  after_state jsonb,
  request_id text,
  ip_address inet,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_audit_log_actor_time_idx ON admin_audit_log (actor_id, created_at DESC);
CREATE INDEX admin_audit_log_target_idx ON admin_audit_log (target_type, target_id, created_at DESC);

CREATE TABLE idempotency_keys (
  scope text NOT NULL,
  key text NOT NULL,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  request_hash bytea NOT NULL,
  response_status integer,
  response_body jsonb,
  locked_until timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope, key)
);
CREATE INDEX idempotency_keys_expiration_idx ON idempotency_keys (expires_at);

CREATE TABLE outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  available_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 0,
  processed_at timestamptz,
  last_error text
);
CREATE INDEX outbox_events_pending_idx ON outbox_events (available_at, occurred_at) WHERE processed_at IS NULL;

CREATE TABLE processed_messages (
  consumer text NOT NULL,
  message_id uuid NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (consumer, message_id)
);

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER quests_set_updated_at BEFORE UPDATE ON quests
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER comments_set_updated_at BEFORE UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER quest_of_the_day_set_updated_at BEFORE UPDATE ON quest_of_the_day
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
