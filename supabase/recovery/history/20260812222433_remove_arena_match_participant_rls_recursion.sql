-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812222433
create or replace function private.is_arena_participant(p_match_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(select 1 from public.arena_participants p where p.match_id=p_match_id and p.user_id=(select auth.uid()) and p.status<>'withdrawn');
$$;

create or replace function private.can_read_arena_match(p_match_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from public.arena_matches m
    where m.id=p_match_id and (
      (m.visibility='public' and m.status in ('open','ready','live','completed'))
      or m.creator_id=(select auth.uid())
      or private.is_arena_participant(m.id)
      or exists(select 1 from public.arena_invites i where i.match_id=m.id and i.invited_user_id=(select auth.uid()))
      or private.is_admin_user()
    )
  );
$$;

revoke all on function private.is_arena_participant(uuid),private.can_read_arena_match(uuid) from public,anon;
grant execute on function private.is_arena_participant(uuid),private.can_read_arena_match(uuid) to authenticated,service_role;

drop policy if exists "Arena matches readable" on public.arena_matches;
create policy "Arena matches readable" on public.arena_matches for select to anon,authenticated
using (
  (visibility='public' and status in ('open','ready','live','completed'))
  or (case when (select auth.uid()) is not null then private.can_read_arena_match(id) else false end)
);

drop policy if exists "Arena participants readable" on public.arena_participants;
create policy "Arena participants readable" on public.arena_participants for select to anon,authenticated
using (
  exists(select 1 from public.arena_matches m where m.id=match_id and m.visibility='public' and m.status in ('open','ready','live','completed'))
  or (case when (select auth.uid()) is not null then private.can_read_arena_match(match_id) else false end)
);
;
