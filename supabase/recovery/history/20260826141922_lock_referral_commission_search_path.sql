-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826141922
CREATE OR REPLACE FUNCTION public.create_invitation_commission(p_inviter uuid, p_registered uuid, p_code text, p_registration uuid, p_amount numeric, p_currency text DEFAULT 'ETB'::text)
RETURNS public.invitation_commissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_row public.invitation_commissions;
  v_cfg public.referral_program_config%rowtype;
begin
  if p_inviter is null or p_registered is null or p_inviter=p_registered then raise exception 'Invalid invitation attribution'; end if;
  if p_code is null or length(trim(p_code))=0 then raise exception 'Invitation code is required'; end if;
  select * into v_cfg from public.referral_program_config where id=true for update;
  if not found or not v_cfg.enabled then raise exception 'Referral program is disabled'; end if;
  if upper(coalesce(p_currency,'ETB')) <> upper(v_cfg.currency) then raise exception 'Commission currency mismatch'; end if;
  if p_amount is null or p_amount <> v_cfg.commission_amount then raise exception 'Commission amount must match configured referral amount'; end if;
  insert into public.invitation_commissions(inviter_user_id,registered_user_id,invitation_code,registration_id,amount,currency,transaction_reference,eligibility_reason)
  values(p_inviter,p_registered,trim(p_code),p_registration,v_cfg.commission_amount,v_cfg.currency,'INV-'||upper(replace(public.gen_random_uuid()::text,'-','')),'Eligible registration invitation')
  on conflict (registered_user_id) where status <> 'cancelled' do nothing returning * into v_row;
  return v_row;
end;
$function$;
;
