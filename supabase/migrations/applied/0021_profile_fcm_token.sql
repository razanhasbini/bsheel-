-- Add FCM token column to profiles for targeted push notifications
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
