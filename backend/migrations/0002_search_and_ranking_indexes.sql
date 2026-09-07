CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX profiles_username_search_idx
  ON profiles USING gin (lower(username::text) gin_trgm_ops);
CREATE INDEX profiles_display_name_search_idx
  ON profiles USING gin (lower(display_name) gin_trgm_ops);
CREATE INDEX profiles_leaderboard_idx
  ON profiles (xp DESC, created_at ASC, id);

CREATE INDEX quests_title_search_idx
  ON quests USING gin (lower(title) gin_trgm_ops)
  WHERE is_active;
CREATE INDEX quests_description_search_idx
  ON quests USING gin (lower(description) gin_trgm_ops)
  WHERE is_active;
CREATE INDEX quests_category_search_idx
  ON quests USING gin (lower(category) gin_trgm_ops)
  WHERE is_active;
