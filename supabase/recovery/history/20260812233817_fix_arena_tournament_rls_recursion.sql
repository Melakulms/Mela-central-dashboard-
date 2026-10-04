-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812233817
create or replace function private.is_arena_tournament_team_member(p_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.arena_tournament_team_members tm where tm.team_id=p_team_id and tm.user_id=(select auth.uid()));
$$;
create or replace function private.can_manage_arena_tournament_team(p_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.arena_tournament_teams tt join public.arena_tournaments t on t.id=tt.tournament_id where tt.id=p_team_id and (tt.captain_id=(select auth.uid()) or t.created_by=(select auth.uid()) or private.is_admin_user()));
$$;
revoke execute on function private.is_arena_tournament_team_member(uuid),private.can_manage_arena_tournament_team(uuid) from public,anon;
grant execute on function private.is_arena_tournament_team_member(uuid),private.can_manage_arena_tournament_team(uuid) to authenticated;

drop policy if exists "Arena tournament teams readable" on public.arena_tournament_teams;
create policy "Arena tournament teams readable" on public.arena_tournament_teams for select to authenticated using (captain_id=(select auth.uid()) or private.is_arena_tournament_team_member(id) or exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()))) or private.is_admin_user());

drop policy if exists "Arena tournament team members readable" on public.arena_tournament_team_members;
create policy "Arena tournament team members readable" on public.arena_tournament_team_members for select to authenticated using (user_id=(select auth.uid()) or private.can_manage_arena_tournament_team(team_id));

drop policy if exists "Arena tournament competitors readable" on public.arena_tournament_competitors;
create policy "Arena tournament competitors readable" on public.arena_tournament_competitors for select to authenticated using (user_id=(select auth.uid()) or (tournament_team_id is not null and private.is_arena_tournament_team_member(tournament_team_id)) or exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()))) or private.is_admin_user());

drop policy if exists "Arena tournament rounds readable" on public.arena_tournament_rounds;
create policy "Arena tournament rounds readable" on public.arena_tournament_rounds for select to authenticated using (exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()) or exists(select 1 from public.arena_tournament_competitors c where c.tournament_id=t.id and (c.user_id=(select auth.uid()) or (c.tournament_team_id is not null and private.is_arena_tournament_team_member(c.tournament_team_id)))))) or private.is_admin_user());

drop policy if exists "Arena rewards readable" on public.arena_rewards;
create policy "Arena rewards readable" on public.arena_rewards for select to authenticated using (beneficiary_user_id=(select auth.uid()) or (beneficiary_arena_team_id is not null and private.is_arena_team_member(beneficiary_arena_team_id)) or (beneficiary_tournament_team_id is not null and private.is_arena_tournament_team_member(beneficiary_tournament_team_id)) or private.is_admin_user());
;
