-- Fix FK consistency: comments and follows should reference profiles, not auth.users
-- This ensures cascade deletes work through the profiles table.

ALTER TABLE public.comments
  DROP CONSTRAINT IF EXISTS comments_user_id_fkey,
  ADD CONSTRAINT comments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.follows
  DROP CONSTRAINT IF EXISTS follows_follower_id_fkey,
  ADD CONSTRAINT follows_follower_id_fkey
    FOREIGN KEY (follower_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.follows
  DROP CONSTRAINT IF EXISTS follows_following_id_fkey,
  ADD CONSTRAINT follows_following_id_fkey
    FOREIGN KEY (following_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
