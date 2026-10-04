-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825202409
CREATE OR REPLACE FUNCTION public.mark_invitation_commission_paid(p_commission_id uuid, p_actor_id uuid DEFAULT NULL::uuid)
RETURNS public.invitation_commissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare v public.invitation_commissions; v_actor uuid;
begin
  v_actor := coalesce(p_actor_id, (select auth.uid()));
  if v_actor is null or not exists (select 1 from public.profiles p where p.id=v_actor and p.role='admin'::public.user_role) then raise exception 'Admin authorization required'; end if;
  if p_commission_id is null then raise exception 'Commission ID is required'; end if;
  select * into v from public.invitation_commissions where id=p_commission_id for update;
  if v.id is null then raise exception 'Commission not found'; end if;
  if v.status='cancelled' then raise exception 'Cancelled commission cannot be paid'; end if;
  if v.status='paid' then return v; end if;
  if v.status not in ('pending','eligible') then raise exception 'Invalid commission state: %', v.status; end if;
  update public.invitation_commissions set status='paid',paid_at=coalesce(paid_at,now()) where id=v.id and status in ('pending','eligible');
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_actor,'mark_invitation_commission_paid','invitation_commission',v.id,jsonb_build_object('amount',v.amount,'currency',v.currency,'previous_status',v.status));
  select * into v from public.invitation_commissions where id=p_commission_id;
  return v;
end;
$function$;
;
