BEGIN;

-- AI proof verification, part 2 (#47): the verification contract and the
-- deterministic forensics layer.
--
-- The finding that drove this. Read Bsheel's own quest catalogue and ask, of
-- each one, *can a photograph establish this at all?*
--
--   "Watch the sunrise"                  — yes, and the capture time proves it
--   "Draw the view from your window"     — yes
--   "Write a six-word story about today" — yes, the text is in the frame
--   "Run to the highest point near you"  — weakly; a vista is consistent, not probative
--   "Read 20 pages of something difficult" — no; a photo of a book shows no page count
--   "Compliment a stranger and mean it"  — no, in principle
--   "Spend an hour with no phone"        — no. The phone took the photograph.
--
-- Roughly a third of the catalogue is cleanly checkable and at least a third
-- cannot be checked from an image at all. Asking a vision model "does this
-- photo prove an hour without a phone" is an incoherent question, and a model
-- asked it will answer anyway, with a confidence score attached. That is how
-- an automated reviewer ends up confidently rejecting honest users — the
-- failure that costs a young app its players.
--
-- So a quest now carries what proof *means* for it, and the agent's authority
-- is a property of the quest rather than a global setting. For quests where
-- content cannot be judged, the question changes from "does this image show
-- the task?" to "is this image authentic, this user's own, and taken inside
-- the quest window?" — which is provenance, and answerable without a model.

-- ── The verification contract ────────────────────────────────────────
CREATE TYPE quest_verifiability AS ENUM ('content', 'provenance_only', 'none');

COMMENT ON TYPE quest_verifiability IS
  'What proof can establish for a quest (#47). content: the image can show '
  'the task. provenance_only: it cannot, but authenticity is checkable. '
  'none: nothing about the image bears on the task — trust unless provenance '
  'actively contradicts.';

-- Category defaults, so a new quest inherits a sane contract instead of
-- needing one authored before it can be reviewed. Five rows to maintain
-- rather than one per quest; they are also the stable cached prefix of the
-- agent's prompt, so keeping the policy at this level is cheaper per call.
CREATE TABLE quest_verification_defaults (
  category         text PRIMARY KEY,
  verifiability    quest_verifiability NOT NULL,
  evidence_rubric  text NOT NULL CHECK (char_length(evidence_rubric) BETWEEN 1 AND 2000),
  -- Authority is per contract, not global. A category whose proof cannot
  -- contradict the task must never be able to auto-reject on content.
  may_auto_approve boolean NOT NULL DEFAULT false,
  may_auto_reject  boolean NOT NULL DEFAULT false,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Per-quest override. Every column nullable: null means "inherit the
-- category default", so an admin overrides only the unusual quest.
ALTER TABLE quests ADD COLUMN IF NOT EXISTS verifiability    quest_verifiability;
ALTER TABLE quests ADD COLUMN IF NOT EXISTS evidence_rubric  text;
ALTER TABLE quests ADD COLUMN IF NOT EXISTS may_auto_approve boolean;
ALTER TABLE quests ADD COLUMN IF NOT EXISTS may_auto_reject  boolean;

ALTER TABLE quests DROP CONSTRAINT IF EXISTS quests_evidence_rubric_check;
ALTER TABLE quests ADD CONSTRAINT quests_evidence_rubric_check
  CHECK (evidence_rubric IS NULL OR char_length(evidence_rubric) BETWEEN 1 AND 2000);

COMMENT ON COLUMN quests.verifiability IS
  'Per-quest override (#47); null inherits quest_verification_defaults.';

-- One place that resolves override-over-default, so the worker, the admin
-- surface and the eval harness cannot disagree about a quest's contract.
-- A quest whose category has no default row is treated as unjudgeable
-- rather than fully automatable: an unknown category must fail safe.
CREATE VIEW quest_verification_contract AS
  SELECT q.id AS quest_id,
         q.category,
         COALESCE(q.verifiability, d.verifiability, 'none')::quest_verifiability AS verifiability,
         COALESCE(q.evidence_rubric, d.evidence_rubric,
                  'No rubric is defined for this quest. Escalate to a human.') AS evidence_rubric,
         COALESCE(q.may_auto_approve, d.may_auto_approve, false) AS may_auto_approve,
         COALESCE(q.may_auto_reject,  d.may_auto_reject,  false) AS may_auto_reject
  FROM quests q
  LEFT JOIN quest_verification_defaults d ON d.category = q.category;

COMMENT ON VIEW quest_verification_contract IS
  'Resolved verification contract per quest (#47): per-quest override over '
  'category default, failing closed to none/no-authority.';

-- Seeded defaults.
--
-- `may_auto_reject` is false for EVERY category, deliberately, even though
-- the reject path is built. Authority is earned by measurement, not asserted
-- in a migration: until the eval has scored the agent against real human
-- decisions, nothing here should be able to tell a user their proof is fake.
-- Flipping a category is then a one-row UPDATE backed by a precision number.
--
-- `verifiability` is where the categories genuinely differ, and it is what
-- stops the agent being asked an incoherent question. Note that a category
-- default cannot be right for every quest in it: "Watch the sunrise" and
-- "Spend an hour with no phone" are both adventure, and only one of them is
-- checkable. Those are what the per-quest override is for.
INSERT INTO quest_verification_defaults
  (category, verifiability, evidence_rubric, may_auto_approve, may_auto_reject)
VALUES
  ('creativity', 'content',
   'The made thing should be visible in the frame — a drawing, an object, a piece of writing. '
   'Text quests are satisfied by legible text in the image. Judge whether what is shown is '
   'plausibly the user''s own work made for this quest, not whether it is good.',
   true, false),

  ('fitness', 'content',
   'Expect the activity, its aftermath, or the place it happened. Counts and durations '
   '("50 push-ups", "30 minutes") CANNOT be verified from an image — never reject for failing '
   'to show a count. A capture time can verify a time clause such as "before noon". '
   'Reject only when the image plainly has nothing to do with physical activity.',
   true, false),

  ('adventure', 'content',
   'Expect the place or the moment. A capture time strongly corroborates a time-bound quest '
   'such as a sunrise. Travel, distance and duration cannot be established from an image. '
   'Some adventure quests are unverifiable in principle and should carry a per-quest override.',
   true, false),

  ('learning', 'provenance_only',
   'What was learned is not visible. A photo of a book, a screen or notes cannot establish '
   'that pages were read or a skill acquired. Do not attempt to judge the learning. Approve '
   'unless provenance fails — recycled, stolen, generated, or captured outside the quest '
   'window. Never reject because the image does not prove the lesson.',
   true, false),

  ('social', 'none',
   'These are unfalsifiable by photograph. Complimenting a stranger, calling someone, or '
   'eating with a new person leave no photographic proof, and demanding one punishes honest '
   'users. Judge authenticity only. Never reject on content. Note that a call-log screenshot '
   'is an honest attempt here, not evidence of fraud.',
   true, false)
ON CONFLICT (category) DO NOTHING;

-- ── Deterministic forensics ──────────────────────────────────────────
-- Computed once per uploaded object, with no model involved. For the large
-- part of the catalogue that content analysis cannot serve, this is the whole
-- signal — and it is the strongest signal available even where content can be
-- judged, because a photograph captured before the quest was assigned is
-- recycled whatever it depicts.
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS captured_at   timestamptz;
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS width         integer CHECK (width  IS NULL OR width  > 0);
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS height        integer CHECK (height IS NULL OR height > 0);
-- 64-bit difference hash. bit(64) rather than bytea so near-duplicate search
-- is `bit_count(a # b) <= threshold` in SQL — Postgres 14+ computes Hamming
-- distance natively, so this needs no extension.
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS perceptual_hash bit(64);
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS forensics     jsonb;
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS forensics_at  timestamptz;

COMMENT ON COLUMN media_objects.captured_at IS
  'EXIF DateTimeOriginal (#47). Null when absent, which is itself a signal: '
  'a camera photograph normally carries one and a screenshot does not.';
COMMENT ON COLUMN media_objects.perceptual_hash IS
  'dHash (#47). Near-duplicate search is bit_count(a # b) <= threshold.';
COMMENT ON COLUMN media_objects.forensics IS
  'Forensics report (#47): screenshot and generated-content indicators, EXIF '
  'provenance, and the reasons behind them, for a moderator to read.';

-- Near-duplicate candidates. Only ready submission objects can be recycled
-- proof, so the index covers exactly those. This supports scanning a bounded
-- candidate set; a platform-wide nearest-neighbour search at scale wants an
-- LSH or BK-tree index, which is deliberately not built yet.
CREATE INDEX IF NOT EXISTS media_objects_phash_idx
  ON media_objects (perceptual_hash)
  WHERE perceptual_hash IS NOT NULL AND kind = 'submission'
    AND status = 'ready' AND deleted_at IS NULL;

-- Exact-byte duplicates, which `etag` already recorded and nothing used.
-- Free, and it catches the laziest recycling without decoding an image.
CREATE INDEX IF NOT EXISTS media_objects_etag_idx
  ON media_objects (etag)
  WHERE etag IS NOT NULL AND kind = 'submission'
    AND status = 'ready' AND deleted_at IS NULL;

-- Objects still needing a forensics pass, so the sweep has an index rather
-- than a scan over every upload ever made.
CREATE INDEX IF NOT EXISTS media_objects_forensics_pending_idx
  ON media_objects (created_at)
  WHERE forensics_at IS NULL AND kind = 'submission'
    AND status = 'ready' AND deleted_at IS NULL;

-- ── Shadow mode and decision provenance ──────────────────────────────
-- The agent runs and records, and a flag decides whether it may act. Shipping
-- an approval agent whose accuracy nobody has measured is not a feature, so
-- shadow mode is the default and the eval is what earns it authority.
ALTER TABLE submission_verifications
  ADD COLUMN IF NOT EXISTS acted boolean NOT NULL DEFAULT false;
ALTER TABLE submission_verifications
  ADD COLUMN IF NOT EXISTS forensics jsonb;
-- Which model produced the verdict is already stored in `model`; this records
-- which rung of the cascade it came from, so cost and accuracy can be
-- attributed per stage.
ALTER TABLE submission_verifications
  ADD COLUMN IF NOT EXISTS stage text
    CHECK (stage IS NULL OR stage IN ('forensics', 'triage', 'deep', 'reject_review'));

COMMENT ON COLUMN submission_verifications.acted IS
  'Whether the verdict was acted on (#47). False in shadow mode, where the '
  'verdict is recorded and the human decision remains ground truth.';
COMMENT ON COLUMN submission_verifications.stage IS
  'Which rung of the cascade decided (#47): deterministic forensics, cheap '
  'triage, deep analysis, or the top-model review required before any reject.';

-- The eval set: verdicts paired with the human decision that followed.
-- `acted = false` is the honest slice — where the agent did not influence the
-- outcome it is being scored against.
CREATE INDEX IF NOT EXISTS submission_verifications_shadow_idx
  ON submission_verifications (completed_at)
  WHERE state = 'complete' AND acted = false;

COMMIT;
