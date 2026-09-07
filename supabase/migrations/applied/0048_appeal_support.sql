-- Migration 0048: Add appeal support to submissions
-- appeal_note stores the user's appeal reason
-- appealed flags that this submission was already appealed (prevent re-appeal)

ALTER TABLE public.submissions
  ADD COLUMN IF NOT EXISTS appeal_note text,
  ADD COLUMN IF NOT EXISTS appealed boolean NOT NULL DEFAULT false;
