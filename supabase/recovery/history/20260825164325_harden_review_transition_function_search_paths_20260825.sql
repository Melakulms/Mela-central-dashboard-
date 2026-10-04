-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825164325
create or replace function public.enforce_employer_review_transition()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.status in ('approved','rejected') and nullif(trim(coalesce(new.review_notes,'')),'') is null then
    raise exception 'review reason is required for approval or rejection';
  end if;
  if new.status <> old.status then
    if not ((old.status='pending' and new.status in ('review','approved','rejected'))
         or (old.status='review' and new.status in ('pending','approved','rejected'))
         or (old.status='review_required' and new.status in ('review','approved','rejected'))) then
      raise exception 'invalid employer status transition: % -> %', old.status, new.status;
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.enforce_opportunity_review_transition()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.moderation_status in ('approved','rejected') and nullif(trim(coalesce(new.moderation_notes,'')),'') is null then
    raise exception 'moderation reason is required for approval or rejection';
  end if;
  if new.moderation_status <> old.moderation_status then
    if not ((old.moderation_status='pending' and new.moderation_status in ('approved','rejected','flagged'))
         or (old.moderation_status='flagged' and new.moderation_status in ('pending','approved','rejected'))
         or (old.moderation_status='rejected' and new.moderation_status='pending')
         or (old.moderation_status='approved' and new.moderation_status='flagged')) then
      raise exception 'invalid opportunity moderation transition: % -> %', old.moderation_status, new.moderation_status;
    end if;
  end if;
  if new.moderation_status='approved' then new.verified_active=true; elsif new.moderation_status='rejected' then new.verified_active=false; end if;
  return new;
end;
$function$;
;
