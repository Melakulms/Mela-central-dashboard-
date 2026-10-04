-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002085541
CREATE OR REPLACE FUNCTION private.raise_contract_dispute(p_contract_id uuid, p_reason text)
 RETURNS freelance_contracts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := (select auth.uid()); v_c public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'reason is required'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status not in ('active','disputed') then raise exception 'active contract required'; end if;
  if v_uid<>v_c.freelancer_id and not private.has_employer_access(v_c.employer_id,false) and not private.is_admin_user() then raise exception 'not authorized'; end if;
  if v_c.status='disputed' then return v_c; end if;
  update public.freelance_contracts set status='disputed',funding_status='disputed',updated_at=now() where id=p_contract_id returning * into v_c;
  update public.escrow_transactions set status='disputed',updated_at=now() where contract_id=p_contract_id and status not in ('released','refunded','cancelled');
  insert into public.reports(reporter_id,target_type,target_id,reason,details,status) values(v_uid,'freelance_contract',p_contract_id,'contract_dispute',trim(p_reason),'open');
  return v_c;
end;
$function$

;
