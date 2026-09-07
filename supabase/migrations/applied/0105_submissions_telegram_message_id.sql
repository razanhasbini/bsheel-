-- ============================================================
-- MIGRATION 0105: Track the Telegram message id per submission
--
-- The telegram-notify-submission edge function sends an alert with
-- ✅ Approve / ❌ Reject buttons every time a new submission lands.
-- We need to remember which Telegram message corresponds to which
-- submission so a separate sync function (triggered by UPDATE on
-- submissions.status) can edit the original message — adding the
-- ✅ APPROVED / ❌ REJECTED prefix and removing the buttons —
-- whenever the review happens via the admin web panel instead of
-- via the Telegram bot itself.
--
-- Without this column, web-side reviews leave the Telegram chat
-- looking like the submission still needs action.
-- ============================================================

ALTER TABLE public.submissions
  ADD COLUMN IF NOT EXISTS telegram_message_id bigint;

COMMENT ON COLUMN public.submissions.telegram_message_id IS
  'ID of the Telegram message that carries the Approve/Reject buttons '
  'for this submission. Set by telegram-notify-submission, read by '
  'telegram-sync-submission to edit the message after a web-side review.';
