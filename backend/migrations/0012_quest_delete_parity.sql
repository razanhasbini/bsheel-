ALTER TABLE user_quests
  DROP CONSTRAINT user_quests_quest_id_fkey,
  ADD CONSTRAINT user_quests_quest_id_fkey
    FOREIGN KEY (quest_id) REFERENCES quests(id) ON DELETE CASCADE;

ALTER TABLE submissions
  DROP CONSTRAINT submissions_user_quest_id_fkey,
  ADD CONSTRAINT submissions_user_quest_id_fkey
    FOREIGN KEY (user_quest_id) REFERENCES user_quests(id) ON DELETE CASCADE;
