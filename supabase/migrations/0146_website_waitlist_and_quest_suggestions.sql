-- Website tables for bsheel.app (marketing site).
--
-- The static site inserts directly from the visitor's browser using the
-- publishable key: RLS allows INSERT only for anon; reading and moderating
-- happens in the admin dashboard (WEB SIGNUPS + QUEST IDEAS pages), gated
-- by is_admin(). Additive only — touches no app tables.

create extension if not exists "pgcrypto";

-- ---------- waitlist (email capture for the v1.5 drop) ----------

create table if not exists public.waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       text not null
              check (char_length(email) <= 254 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  source      text check (source is null or char_length(source) <= 40),
  created_at  timestamptz not null default now(),
  unique (email)
);

alter table public.waitlist enable row level security;

drop policy if exists "waitlist_insert_anon" on public.waitlist;
create policy "waitlist_insert_anon"
  on public.waitlist for insert
  to anon
  with check (true);

drop policy if exists "waitlist_select_admin" on public.waitlist;
create policy "waitlist_select_admin"
  on public.waitlist for select
  to authenticated
  using (public.is_admin());

grant insert on public.waitlist to anon;
grant select on public.waitlist to authenticated;

-- ---------- quest_suggestions (community quest ideas) ----------

create table if not exists public.quest_suggestions (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null check (char_length(title) between 3 and 100),
  description         text not null check (char_length(description) between 10 and 500),
  category            text not null check (category in ('fitness','creativity','social','learning','adventure')),
  difficulty          text not null check (difficulty in ('easy','medium','hard')),
  suggested_by_name   text check (suggested_by_name is null or char_length(suggested_by_name) <= 60),
  suggested_by_handle text check (suggested_by_handle is null or char_length(suggested_by_handle) <= 40),
  status              text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at          timestamptz not null default now()
);

alter table public.quest_suggestions enable row level security;

drop policy if exists "quest_suggestions_insert_anon" on public.quest_suggestions;
create policy "quest_suggestions_insert_anon"
  on public.quest_suggestions for insert
  to anon
  with check (status = 'pending');

drop policy if exists "quest_suggestions_select_admin" on public.quest_suggestions;
create policy "quest_suggestions_select_admin"
  on public.quest_suggestions for select
  to authenticated
  using (public.is_admin());

drop policy if exists "quest_suggestions_update_admin" on public.quest_suggestions;
create policy "quest_suggestions_update_admin"
  on public.quest_suggestions for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant insert on public.quest_suggestions to anon;
grant select, update on public.quest_suggestions to authenticated;
