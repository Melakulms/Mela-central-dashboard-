-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812222350
create or replace function private.is_challenge_team_member(p_team_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.challenge_team_members m where m.team_id=p_team_id and m.user_id=(select auth.uid())); $$;

create or replace function private.is_arena_team_member(p_team_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.arena_team_members m where m.team_id=p_team_id and m.user_id=(select auth.uid())); $$;

revoke all on function private.is_challenge_team_member(uuid),private.is_arena_team_member(uuid) from public,anon;
grant execute on function private.is_challenge_team_member(uuid),private.is_arena_team_member(uuid) to authenticated,service_role;

drop policy if exists "Challenge teams readable" on public.challenge_teams;
create policy "Challenge teams readable" on public.challenge_teams for select to authenticated
using (
  private.has_challenge_manage_access(challenge_id)
  or captain_id=(select auth.uid())
  or private.is_challenge_team_member(id)
  or exists(select 1 from public.sponsored_challenges c where c.id=challenge_id and c.status in ('open','judging','completed'))
);

drop policy if exists "Challenge team members readable" on public.challenge_team_members;
create policy "Challenge team members readable" on public.challenge_team_members for select to authenticated
using (
  user_id=(select auth.uid())
  or private.is_challenge_team_member(team_id)
  or exists(select 1 from public.challenge_teams t where t.id=team_id and (t.captain_id=(select auth.uid()) or private.has_challenge_manage_access(t.challenge_id)))
);

drop policy if exists "Challenge rewards readable" on public.challenge_rewards;
create policy "Challenge rewards readable" on public.challenge_rewards for select to authenticated
using (
  beneficiary_user_id=(select auth.uid())
  or (beneficiary_team_id is not null and private.is_challenge_team_member(beneficiary_team_id))
  or private.has_challenge_manage_access(challenge_id)
);

drop policy if exists "Arena teams readable" on public.arena_teams;
create policy "Arena teams readable" on public.arena_teams for select to authenticated
using (
  captain_id=(select auth.uid())
  or private.is_arena_team_member(id)
  or exists(select 1 from public.arena_matches m where m.id=match_id and (m.visibility='public' or m.creator_id=(select auth.uid()) or private.is_admin_user()))
);

drop policy if exists "Arena team members readable" on public.arena_team_members;
create policy "Arena team members readable" on public.arena_team_members for select to authenticated
using (
  user_id=(select auth.uid())
  or private.is_arena_team_member(team_id)
  or exists(select 1 from public.arena_teams t where t.id=team_id and t.captain_id=(select auth.uid()))
);
;
