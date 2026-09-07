-- 65 quests across 5 categories
-- Run in Supabase SQL Editor to populate the quest library

-- FITNESS (13)
INSERT INTO public.quests (title, description, category, difficulty, xp_reward, is_active) VALUES
('MORNING WARRIOR', 'Do 30 push-ups before breakfast. No excuses.', 'fitness', 'easy', 25, true),
('RUN THE BLOCK', 'Run or jog for 15 minutes nonstop around your neighborhood.', 'fitness', 'easy', 30, true),
('STAIRWAY TO GAINS', 'Find a staircase and climb it 10 times without stopping.', 'fitness', 'medium', 50, true),
('PLANK MASTER', 'Hold a plank for 2 minutes total. Break it up if you need to.', 'fitness', 'medium', 40, true),
('SUNSET WALK', 'Take a 30-minute walk during golden hour. No phone scrolling.', 'fitness', 'easy', 25, true),
('BURPEE BOSS', 'Complete 50 burpees. Time yourself and beat your record.', 'fitness', 'hard', 75, true),
('STRETCH IT OUT', 'Do a full 20-minute stretching routine. Touch your toes.', 'fitness', 'easy', 20, true),
('HYDRATION CHECK', 'Drink 3 liters of water today. Track every glass.', 'fitness', 'easy', 20, true),
('COLD SHOWER HERO', 'Take a 2-minute cold shower. Film your reaction.', 'fitness', 'hard', 60, true),
('JUMP ROPE FRENZY', 'Jump rope for 10 minutes. Any style counts.', 'fitness', 'medium', 45, true),
('BIKE EXPLORER', 'Ride a bike for 30 minutes. Explore a new route.', 'fitness', 'medium', 50, true),
('YOGA FLOW', 'Follow a 20-minute yoga video. Screenshot your setup.', 'fitness', 'easy', 30, true),
('100 SQUAT CHALLENGE', 'Do 100 squats throughout the day. Track your sets.', 'fitness', 'hard', 70, true);

-- CREATIVITY (13)
INSERT INTO public.quests (title, description, category, difficulty, xp_reward, is_active) VALUES
('SKETCH SOMETHING', 'Draw anything in 15 minutes. Skill level doesn''t matter.', 'creativity', 'easy', 25, true),
('WRITE A POEM', 'Write a poem about your current mood. At least 8 lines.', 'creativity', 'medium', 40, true),
('PHOTO WALK', 'Take 10 creative photos of everyday objects. Make them art.', 'creativity', 'easy', 30, true),
('BUILD SOMETHING', 'Build something with your hands. Legos, origami, anything.', 'creativity', 'medium', 50, true),
('COOK A NEW RECIPE', 'Make a dish you''ve never tried before. Document the process.', 'creativity', 'medium', 45, true),
('PIXEL ART TIME', 'Create a pixel art piece using any free tool online.', 'creativity', 'medium', 50, true),
('MUSIC MAKER', 'Create a 30-second beat or melody using any app.', 'creativity', 'hard', 60, true),
('WRITE A SHORT STORY', 'Write a 500-word story. Any genre. Just finish it.', 'creativity', 'hard', 70, true),
('REARRANGE YOUR SPACE', 'Redesign a corner of your room. Make it aesthetic.', 'creativity', 'easy', 30, true),
('FILM A MINI VLOG', 'Record a 60-second vlog about your day. Edit it.', 'creativity', 'medium', 45, true),
('DESIGN A LOGO', 'Design a logo for an imaginary brand. Paper or digital.', 'creativity', 'hard', 65, true),
('COLLAGE CREATOR', 'Make a collage from magazine cutouts or digital images.', 'creativity', 'easy', 25, true),
('HANDWRITE A LETTER', 'Write a handwritten letter to someone you care about.', 'creativity', 'easy', 30, true);

-- SOCIAL (13)
INSERT INTO public.quests (title, description, category, difficulty, xp_reward, is_active) VALUES
('CALL A FRIEND', 'Call someone you haven''t talked to in a while. 10+ minutes.', 'social', 'easy', 25, true),
('COMPLIMENT BOMB', 'Give genuine compliments to 5 different people today.', 'social', 'easy', 30, true),
('HELP A STRANGER', 'Do something kind for a stranger. Hold a door, carry bags, anything.', 'social', 'medium', 40, true),
('TECH-FREE HANGOUT', 'Spend 2 hours with friends with zero phone usage.', 'social', 'hard', 60, true),
('SEND A VOICE NOTE', 'Send a thoughtful voice note to 3 people you appreciate.', 'social', 'easy', 20, true),
('TEACH SOMEONE', 'Teach a friend or family member something you''re good at.', 'social', 'medium', 50, true),
('SURPRISE DELIVERY', 'Surprise someone with their favorite snack or drink.', 'social', 'medium', 45, true),
('GROUP PHOTO', 'Get a group photo with 4+ people. Make it creative.', 'social', 'easy', 25, true),
('DEEP CONVERSATION', 'Have a meaningful conversation about life goals with someone.', 'social', 'medium', 40, true),
('VOLUNTEER HOUR', 'Spend 1 hour volunteering or helping in your community.', 'social', 'hard', 75, true),
('FAMILY TIME', 'Spend 1 hour of quality time with family. No screens.', 'social', 'easy', 30, true),
('MAKE SOMEONE LAUGH', 'Make 3 people genuinely laugh today. Dad jokes count.', 'social', 'easy', 20, true),
('RECONNECT', 'Message someone you lost touch with and catch up.', 'social', 'easy', 25, true);

-- LEARNING (13)
INSERT INTO public.quests (title, description, category, difficulty, xp_reward, is_active) VALUES
('READ 30 PAGES', 'Read 30 pages of any book. Fiction or non-fiction.', 'learning', 'easy', 25, true),
('WATCH A DOCUMENTARY', 'Watch a documentary about something you know nothing about.', 'learning', 'easy', 30, true),
('LEARN 10 WORDS', 'Learn 10 words in a new language. Practice pronunciation.', 'learning', 'medium', 40, true),
('TUTORIAL TIME', 'Follow a tutorial and learn a new skill. Code, cook, craft.', 'learning', 'medium', 50, true),
('TED TALK MARATHON', 'Watch 3 TED talks and write down your key takeaways.', 'learning', 'easy', 30, true),
('JOURNAL SESSION', 'Write a 1-page journal entry reflecting on your week.', 'learning', 'easy', 20, true),
('SOLVE A PUZZLE', 'Complete a crossword, sudoku, or logic puzzle.', 'learning', 'easy', 20, true),
('LEARN AN INSTRUMENT', 'Practice an instrument for 30 minutes. Any level.', 'learning', 'medium', 45, true),
('WIKIPEDIA DEEP DIVE', 'Start on any Wikipedia page and read for 30 minutes.', 'learning', 'easy', 25, true),
('PODCAST QUEST', 'Listen to a full podcast episode on a topic new to you.', 'learning', 'easy', 25, true),
('CODE SOMETHING', 'Write a small program or script. Any language.', 'learning', 'hard', 65, true),
('MEMORY PALACE', 'Memorize 15 random items using a memory technique.', 'learning', 'hard', 60, true),
('TEACH YOURSELF', 'Watch a YouTube tutorial and practice the skill for 1 hour.', 'learning', 'medium', 45, true);

-- ADVENTURE (13)
INSERT INTO public.quests (title, description, category, difficulty, xp_reward, is_active) VALUES
('NEW ROUTE', 'Take a completely different route to a place you go regularly.', 'adventure', 'easy', 25, true),
('TRY NEW FOOD', 'Eat something you''ve never tried before. Rate it 1-10.', 'adventure', 'easy', 25, true),
('EXPLORE A NEW AREA', 'Visit a neighborhood or area you''ve never been to.', 'adventure', 'medium', 45, true),
('SUNRISE MISSION', 'Wake up early enough to watch the sunrise. Photo proof.', 'adventure', 'hard', 60, true),
('TALK TO A LOCAL', 'Start a conversation with a shop owner or local you don''t know.', 'adventure', 'medium', 40, true),
('NIGHT WALK', 'Take a 20-minute walk after 9 PM. Notice the different vibe.', 'adventure', 'easy', 25, true),
('FIND STREET ART', 'Find and photograph 3 pieces of street art in your city.', 'adventure', 'medium', 40, true),
('VISIT A BOOKSTORE', 'Spend 30 minutes in a bookstore. Buy something unexpected.', 'adventure', 'easy', 30, true),
('ROOFTOP VIEW', 'Find the highest accessible point near you and take in the view.', 'adventure', 'medium', 50, true),
('MARKET RUN', 'Visit a local market or bazaar you''ve never been to.', 'adventure', 'easy', 30, true),
('NATURE ESCAPE', 'Spend 1 hour in nature. Park, forest, beach, mountain.', 'adventure', 'medium', 45, true),
('CAFE HOPPER', 'Visit a cafe you''ve never been to. Try their signature drink.', 'adventure', 'easy', 25, true),
('RANDOM BUS RIDE', 'Take a random bus and get off at an interesting stop. Explore.', 'adventure', 'hard', 70, true);
