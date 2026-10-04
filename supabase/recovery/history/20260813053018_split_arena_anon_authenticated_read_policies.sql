-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813053018
drop policy if exists "Arena matches readable" on public.arena_matches;
create policy "Arena matches public discovery" on public.arena_matches for select to anon using (visibility='public' and status in ('open','ready','live','completed'));
create policy "Arena matches authenticated read" on public.arena_matches for select to authenticated using ((visibility='public' and status in ('open','ready','live','completed')) or private.can_read_arena_match(id));

drop policy if exists "Arena participants readable" on public.arena_participants;
create policy "Arena participants public scoreboard" on public.arena_participants for select to anon using (exists(select 1 from public.arena_matches m where m.id=match_id and m.visibility='public' and m.status in ('open','ready','live','completed')));
create policy "Arena participants authenticated read" on public.arena_participants for select to authenticated using ((exists(select 1 from public.arena_matches m where m.id=match_id and m.visibility='public' and m.status in ('open','ready','live','completed'))) or private.can_read_arena_match(match_id));

drop policy if exists "Arena seasons public read" on public.arena_seasons;
create policy "Arena seasons anon public read" on public.arena_seasons for select to anon using (visibility='public' and status in ('open','active','completed'));
create policy "Arena seasons authenticated read" on public.arena_seasons for select to authenticated using ((visibility='public' and status in ('open','active','completed')) or created_by=(select auth.uid()) or private.is_admin_user());

drop policy if exists "Arena tournaments public read" on public.arena_tournaments;
create policy "Arena tournaments anon public read" on public.arena_tournaments for select to anon using (visibility='public' and status in ('registration','in_progress','completed'));
create policy "Arena tournaments authenticated read" on public.arena_tournaments for select to authenticated using ((visibility='public' and status in ('registration','in_progress','completed')) or created_by=(select auth.uid()) or private.is_admin_user());
;
