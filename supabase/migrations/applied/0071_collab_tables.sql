-- ============================================================
-- MIGRATION 0071: Collaborative quest groups (v2)
-- Supports up to 5 members, WITH and VERSUS modes.
-- Replaces the old collab_pairs / collab_invites design.
-- ============================================================

DROP TABLE IF EXISTS public.collab_pairs CASCADE;
DROP TABLE IF EXISTS public.collab_invites CASCADE;

-- ── Group table ─────────────────────────────────────────────

CREATE TABLE public.collab_groups (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  quest_id    uuid        NOT NULL REFERENCES public.quests(id),
  creator_id  uuid        NOT NULL REFERENCES auth.users(id),
  code        text        NOT NULL,
  mode        text        NOT NULL CHECK (mode IN ('with', 'versus')),
  status      text        NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open', 'closed', 'expired')),
  max_members integer     NOT NULL DEFAULT 5 CHECK (max_members BETWEEN 2 AND 5),
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_collab_group_code UNIQUE (code)
);

CREATE INDEX idx_collab_groups_code ON public.collab_groups (code) WHERE status = 'open';

-- ── Members table ───────────────────────────────────────────

CREATE TABLE public.collab_group_members (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id                uuid        NOT NULL REFERENCES public.collab_groups(id) ON DELETE CASCADE,
  user_id                 uuid        NOT NULL REFERENCES auth.users(id),
  user_quest_id           uuid        NOT NULL REFERENCES public.user_quests(id) ON DELETE CASCADE,
  joined_at               timestamptz NOT NULL DEFAULT now(),
  submission_time_seconds integer,

  CONSTRAINT uq_group_member UNIQUE (group_id, user_id)
);

CREATE INDEX idx_collab_members_group ON public.collab_group_members (group_id);
CREATE INDEX idx_collab_members_user_quest ON public.collab_group_members (user_quest_id);

-- ── Votes table (VERSUS mode) ───────────────────────────────

CREATE TABLE public.collab_votes (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid        NOT NULL REFERENCES public.collab_groups(id) ON DELETE CASCADE,
  voter_id      uuid        NOT NULL REFERENCES auth.users(id),
  submission_id uuid        NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_one_vote_per_user_per_group UNIQUE (group_id, voter_id)
);

-- ── RLS ─────────────────────────────────────────────────────

ALTER TABLE public.collab_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collab_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collab_votes ENABLE ROW LEVEL SECURITY;

-- Groups: readable by members
CREATE POLICY collab_groups_select ON public.collab_groups
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.collab_group_members
      WHERE group_id = collab_groups.id AND user_id = auth.uid()
    )
    OR status = 'open' -- allow previewing open groups by code lookup
  );

-- Members: readable by fellow group members
CREATE POLICY collab_members_select ON public.collab_group_members
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.collab_group_members m2
      WHERE m2.group_id = collab_group_members.group_id AND m2.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.collab_groups g
      WHERE g.id = collab_group_members.group_id AND g.status = 'open'
    )
  );

-- Votes: readable by anyone (public vote counts on feed)
CREATE POLICY collab_votes_select ON public.collab_votes
  FOR SELECT TO authenticated USING (true);
