-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002085113
CREATE OR REPLACE FUNCTION private.finish_arena(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_m public.arena_matches; v_uid uuid := (select auth.uid());
begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null then raise exception 'arena not found'; end if;
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_m.creator_id is distinct from v_uid and not private.is_admin_user() then raise exception 'arena creator access required'; end if;
  if v_m.status='completed' then return; end if;
  if v_m.status<>'live' then raise exception 'only a live arena can be finished'; end if;
  if not private.is_admin_user() and v_m.round_ends_at is not null and v_m.round_ends_at>now() then
    raise exception 'live arena cannot be finished before the current round ends';
  end if;
  if not private.is_admin_user() and exists(select 1 from public.arena_rounds r where r.match_id=p_match_id and r.round_order>coalesce(v_m.current_round_order,0)) then
    raise exception 'all arena rounds must finish before completing the match';
  end if;
  perform private.finalize_arena_match(p_match_id);
end $function$

;
