ALTER TABLE quest_of_the_day ADD COLUMN note text CHECK (char_length(note) <= 1000);

ALTER TABLE quest_suggestions
  ADD COLUMN category text CHECK (category IS NULL OR char_length(category) <= 80),
  ADD COLUMN difficulty text CHECK (difficulty IS NULL OR difficulty IN ('easy', 'medium', 'hard')),
  ADD COLUMN suggested_by_name text CHECK (suggested_by_name IS NULL OR char_length(suggested_by_name) <= 80),
  ADD COLUMN suggested_by_handle text CHECK (suggested_by_handle IS NULL OR char_length(suggested_by_handle) <= 80);
