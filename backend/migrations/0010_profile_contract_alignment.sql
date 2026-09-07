ALTER TABLE profiles ALTER COLUMN display_name SET DEFAULT 'New User';

ALTER TABLE profiles DROP CONSTRAINT profiles_display_name_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_display_name_check
  CHECK (char_length(display_name) BETWEEN 1 AND 50);

ALTER TABLE profiles DROP CONSTRAINT profiles_bio_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_bio_check
  CHECK (bio IS NULL OR char_length(bio) <= 300);
