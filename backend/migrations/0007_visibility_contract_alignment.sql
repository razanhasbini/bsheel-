-- Match the Flutter/Supabase contract. This is a PostgreSQL enum rename, so
-- existing rows keep their value and no data rewrite is required.
ALTER TYPE submission_visibility RENAME VALUE 'hidden' TO 'hidden_from_feed';
