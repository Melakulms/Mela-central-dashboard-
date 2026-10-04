-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826134942
CREATE OR REPLACE FUNCTION public.admin_review_opportunity(p_opportunity_id uuid, p_status text, p_moderation_notes text)
RETURNS public.opportunities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare r public.opportunities;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if p_opportunity_id is null then raise exception 'opportunity id is required'; end if;
  if p_status not in ('approved','rejected','pending','flagged') then raise exception 'invalid moderation status'; end if;
  if p_status in ('approved','rejected') and nullif(trim(coalesce(p_moderation_notes,'')),'') is null then raise exception 'review reason is required'; end if;
  update public.opportunities
     set moderation_status=p_status,
         moderation_notes=nullif(trim(coalesce(p_moderation_notes,'')),''),
         verified_active=(p_status='approved'),
         updated_at=now()
   where id=p_opportunity_id
     and moderation_status in ('pending','flagged','rejected','approved')
     and ((moderation_status='pending' and p_status in ('approved','rejected','flagged')) or
          (moderation_status='flagged' and p_status in ('pending','approved','rejected')) or
          (moderation_status='rejected' and p_status='pending') or
          (moderation_status='approved' and p_status='flagged'))
  returning * into r;
  if not found then raise exception 'invalid transition or concurrent modification'; end if;
  return r;
end;
$function$;
;
