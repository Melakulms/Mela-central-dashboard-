-- Approved/rejected opportunities need a moderation reason when entering that state,
-- not on every unrelated maintenance update while already in that state.
create or replace function public.enforce_opportunity_review_transition()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.moderation_status in ('approved','rejected')
     and new.moderation_status is distinct from old.moderation_status
     and nullif(trim(coalesce(new.moderation_notes,'')),'') is null then
    raise exception 'Moderation reason is required';
  end if;

  if new.moderation_status is distinct from old.moderation_status and not (
    (old.moderation_status='pending_review' and new.moderation_status in ('approved','rejected','flagged'))
    or (old.moderation_status='flagged' and new.moderation_status in ('pending_review','approved','rejected','suspended'))
    or (old.moderation_status='rejected' and new.moderation_status='pending_review')
    or (old.moderation_status='approved' and new.moderation_status in ('pending_review','flagged','suspended','archived'))
    or (old.moderation_status='suspended' and new.moderation_status in ('pending_review','archived'))
  ) then
    raise exception 'Invalid opportunity review transition: % -> %',old.moderation_status,new.moderation_status;
  end if;

  if new.moderation_status='approved'
     and new.moderation_status is distinct from old.moderation_status
     and new.status='pending_review' then
    new.status:='open';
  end if;

  if new.moderation_status<>'approved' then new.verified_active:=false; end if;
  return new;
end;
$function$;
