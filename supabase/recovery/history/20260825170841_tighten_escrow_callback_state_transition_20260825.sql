-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825170841
create or replace function public.finalize_escrow_payment(p_payment_id uuid, p_provider_ref text, p_provider_method text, p_provider_type text, p_provider_charge numeric, p_verify_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_p public.escrow_payment_attempts%rowtype; v_e public.escrow_transactions%rowtype;
begin
 select * into v_p from public.escrow_payment_attempts where id=p_payment_id for update;
 if v_p.id is null then raise exception 'escrow payment attempt not found'; end if;
 if v_p.status='success' then return jsonb_build_object('status','success','payment_id',v_p.id,'escrow_id',v_p.escrow_id,'tx_ref',v_p.tx_ref,'idempotent',true); end if;
 if v_p.status not in ('initiated','pending') then raise exception 'payment is not finalizable in current state'; end if;
 if nullif(trim(coalesce(p_provider_ref,'')),'') is null then raise exception 'provider reference required'; end if;
 if p_provider_charge is null or p_provider_charge<>v_p.expected_amount_minor then raise exception 'provider charge does not match expected amount'; end if;
 select * into v_e from public.escrow_transactions where id=v_p.escrow_id for update;
 if v_e.id is null then raise exception 'escrow transaction not found'; end if;
 if v_e.transaction_type<>'funding' or v_e.milestone_id is null then raise exception 'invalid milestone funding escrow'; end if;
 if v_e.amount_minor<>v_p.expected_amount_minor then raise exception 'escrow amount does not match payment amount'; end if;
 if v_e.status not in ('pending_funding','funding_pending','failed','held') then raise exception 'escrow cannot be funded from status %',v_e.status; end if;
 update public.escrow_payment_attempts set status='success',provider_status='success',provider_ref=p_provider_ref,provider_method=p_provider_method,provider_type=p_provider_type,provider_charge=p_provider_charge,verify_payload=coalesce(p_verify_payload,'{}'::jsonb),failure_reason=null,paid_at=coalesce(paid_at,now()),last_verified_at=now(),updated_at=now() where id=v_p.id;
 if v_e.status<>'held' then update public.escrow_transactions set status='held',provider=coalesce(p_provider_method,v_e.provider),external_ref=v_p.tx_ref,funded_at=coalesce(funded_at,now()),updated_at=now() where id=v_e.id; end if;
 return jsonb_build_object('status','success','payment_id',v_p.id,'escrow_id',v_e.id,'tx_ref',v_p.tx_ref,'idempotent',false);
end;
$$;
revoke all on function public.finalize_escrow_payment(uuid,text,text,text,numeric,jsonb) from public, anon, authenticated;
grant execute on function public.finalize_escrow_payment(uuid,text,text,text,numeric,jsonb) to service_role;
;
