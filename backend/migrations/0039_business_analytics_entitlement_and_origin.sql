BEGIN;

-- Two gaps in #50, which asked for "a dynamic whitelist analytics dashboard
-- that displays to every business subscribed with bsheel analytics" and for
-- "country touristic analytics".

-- 1. The whitelist.
--
-- `businesses.status` is a moderation state — active or suspended — and it
-- was standing in for entitlement, which meant every business that existed
-- got the full analytics dashboard. Those are different questions: a
-- business in perfectly good standing may simply not be subscribed to
-- analytics, and suspending one for a content dispute is not the same act as
-- ending its subscription.
--
-- A timestamp rather than a boolean, because "since when" is the question
-- anyone asks next (billing periods, trials, churn), and a boolean throws
-- that away for no saving. NULL means not subscribed, which is the default:
-- entitlement is granted deliberately, never inherited by existing.
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS analytics_subscribed_at timestamptz;

COMMENT ON COLUMN businesses.analytics_subscribed_at IS
  'When analytics access was granted. NULL = not subscribed; the dashboard is refused.';

-- 2. Where visitors come from.
--
-- There was no country on a user at all, so #50's tourism analytics had no
-- data source of any kind. This is the source: self-declared, coarse, and
-- optional.
--
-- Deliberately NOT a foreign key to map_countries. That table is the game
-- board — the countries Bsheel publishes places in, currently two — whereas
-- a player can be from anywhere. An FK would reject the true answer for
-- almost every real user and push them into lying or leaving it blank.
--
-- Deliberately NOT derived from CAMARA either. The network knows where a
-- device is, and turning that into a stored "home country" would be
-- inferring a person's residence from telecom data they gave us for
-- verifying one quest. Two letters someone typed into their own profile is
-- both more accurate and less of an imposition.
--
-- ISO 3166-1 alpha-2, uppercase, enforced here so aggregation never has to
-- fold case or trim.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS country_code text
    CONSTRAINT profiles_country_code_format CHECK (country_code ~ '^[A-Z]{2}$');

COMMENT ON COLUMN profiles.country_code IS
  'Self-declared ISO 3166-1 alpha-2 home country. Optional. Surfaced to '
  'businesses only in aggregate, only with analytics consent, and only above '
  'the minimum cohort size.';

-- The origin breakdown groups by country across the visitors of one
-- business's places. Those visitors are reached through submissions, so this
-- index is what stops the grouping degrading into a full profiles scan as
-- the table grows. Partial, because a NULL country contributes nothing to
-- any bucket except the undisclosed total.
CREATE INDEX IF NOT EXISTS profiles_country_code_idx
  ON profiles (country_code)
  WHERE country_code IS NOT NULL;

COMMIT;
