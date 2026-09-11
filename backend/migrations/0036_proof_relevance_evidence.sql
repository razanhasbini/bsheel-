BEGIN;

-- AI proof verification, part 3 (#47): media relevance as a stored, separate
-- signal, and the bridge that lets the CAMARA agent see through the vision
-- pass instead of guessing.
--
-- The gap this closes. Until now the agent pipeline (modules/agent, #53)
-- received `CvEvidence` from a provider that was `none` on every deployment,
-- so its whole knowledge of the submitted media was `mediaCount` — the number
-- of files attached. It could tell that proof had been uploaded and nothing
-- whatsoever about what was in it. Meanwhile the vision cascade (#47,
-- modules/submissions) looked at the media properly and kept its conclusion
-- to itself. One system had eyes, the other had authority.
--
-- Two columns are what the bridge needs.
--
-- `relevance` is NOT a second confidence score, and conflating the two is the
-- mistake this column exists to prevent:
--
--   confidence — how sure the analyzer is of its own verdict
--   relevance  — how much the media has to do with the quest at all
--
-- They are orthogonal, and the pair says more than either. A model can be
-- *very* sure that a photograph of a cat is irrelevant to "watch the sunrise"
-- (confidence 0.95, relevance 0.02), and genuinely unsure about a hazy
-- half-lit horizon that probably is one (confidence 0.40, relevance 0.85).
-- Storing relevance separately is what makes "the AI checked whether the
-- media actually matches the quest" an auditable number in the review queue
-- rather than a claim about a prompt.
--
-- The trap, and why relevance alone may never reject anyone: low relevance is
-- the NORMAL and CORRECT state for most of the catalogue. A photograph of a
-- coffee cup is irrelevant to "compliment a stranger" — and the submission is
-- honest. Relevance is admissible evidence only where
-- quest_verification_contract.verifiability = 'content'. Everywhere else it is
-- recorded and ignored, which is the same rule migration 0034 established for
-- content analysis generally.
--
-- `content_evidence` holds what the analyzer actually observed — the typed
-- action/object/landmark/location-cue list — so the agent's own reasoning can
-- cite specifics ("no sunrise, no horizon; an indoor ceiling light") instead
-- of receiving a bare score. It is also what the eval needs to tell a wrong
-- verdict from a wrong *observation*, which are different bugs with different
-- fixes.

ALTER TABLE submission_verifications
  ADD COLUMN IF NOT EXISTS relevance numeric(4, 3)
    CHECK (relevance IS NULL OR relevance BETWEEN 0 AND 1);

ALTER TABLE submission_verifications
  ADD COLUMN IF NOT EXISTS content_evidence jsonb
    CHECK (content_evidence IS NULL OR jsonb_typeof(content_evidence) = 'object');

COMMENT ON COLUMN submission_verifications.relevance IS
  'How much the submitted media has to do with the quest, 0..1 (#47). NOT '
  'confidence, which is how sure the analyzer is of its verdict — the two are '
  'orthogonal and both are stored. Null when no content analysis ran, which '
  'is correct for provenance_only/none quests. Admissible only where the '
  'quest contract says verifiability = content: low relevance is the normal '
  'state for a quest no photograph can show, and must never reject anyone.';

COMMENT ON COLUMN submission_verifications.content_evidence IS
  'What the vision pass observed against the quest (#47): typed '
  'action/object/landmark/location-cue detections, each with its own '
  'confidence and a present flag so a recorded ABSENCE survives. Read by the '
  'agent pipeline as CvEvidence.detections so one vision pass serves both '
  'verifiers. The integrity half of that evidence is NOT here — it is derived '
  'at read time from the separate `forensics` column, because it is a '
  'measurement of the file rather than something the model reported.';

-- No index on `relevance`, deliberately.
--
-- Both moderator projections and the eval fetch by submission_id or scan the
-- completed shadow slice and compute in JavaScript; nothing filters or sorts
-- on this column. An index for a query nobody writes costs every insert and
-- pays back nothing, and `submission_verifications_shadow_idx` from 0034
-- already covers the slice the eval actually walks.

COMMIT;
