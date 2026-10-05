begin;
do $test$
declare
 actor uuid:=gen_random_uuid();
 inviter uuid:=gen_random_uuid();
 product text;
 pay uuid;
 provider_ref text:='LOCAL-TEST-'||gen_random_uuid()::text;
 code_value text;
 result jsonb;
 first_entitlement uuid;
 commission public.invitation_commissions;
 blocked boolean:=false;
begin
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 values(actor,actor::text||'@example.invalid','{"provider":"email"}','{"role":"student","full_name":"Learning payment contract test"}',now(),now()),
 (inviter,inviter::text||'@example.invalid','{"provider":"email"}','{"role":"student","full_name":"Premium referral test"}',now(),now());
 select product_key into product from public.mela_learning_products where product_type='subscription' and billing_period='monthly' limit 1;
 if product is null then raise exception 'Monthly product fixture unavailable'; end if;
 update public.mela_learning_products set active=true,sale_enabled=true,active_price_minor=5000,currency='ETB' where product_key=product;
 insert into public.mela_learning_payment_attempts(user_id,product_key,mode,tx_ref,expected_amount_minor,expected_currency,status)
 values(actor,product,'test',provider_ref,5000,'ETB','pending') returning id into pay;
 perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor)::text,true);
 begin
  update public.mela_learning_payment_attempts set status='success' where id=pay;
 exception when insufficient_privilege then blocked:=true;
 end;
 if not blocked then raise exception 'Client identity could mark payment successful'; end if;
 perform set_config('request.jwt.claims','{}',true);
 blocked:=false;
 begin
  perform public.finalize_mela_learning_payment(pay,provider_ref,'test','test',0.25,'{}');
 exception when others then
  if sqlerrm not like '%provider charge does not match expected amount%' then raise; end if;
  blocked:=true;
 end;
 if not blocked then raise exception 'Provider fee incorrectly accepted as payment amount'; end if;
 result:=public.finalize_mela_learning_payment(pay,provider_ref,'test','test',5000,'{}');
 first_entitlement:=(result->>'entitlement_id')::uuid;
 if first_entitlement is null or not exists(select 1 from public.user_subscriptions where user_id=actor and status='premium_active') then raise exception 'Verified full amount did not activate premium'; end if;
 result:=public.finalize_mela_learning_payment(pay,provider_ref,'test','test',5000,'{}');
 if (result->>'idempotent')::boolean is distinct from true or (result->>'entitlement_id')::uuid is distinct from first_entitlement then raise exception 'Repeated settlement was not idempotent'; end if;
 update public.referral_program_config set enabled=true,free_commission_amount=10,premium_commission_amount=20,currency='ETB' where id=true;
 select code into code_value from public.referral_codes where owner_user_id=inviter and active limit 1;
 if code_value is null then raise exception 'Referral code not generated'; end if;
 commission:=public.process_registration_invitation(actor,code_value);
 if commission.amount<>20 or commission.invitee_tier<>'premium' or commission.status<>'pending' then raise exception 'Premium provisional commission is not 20 ETB pending'; end if;
 if exists(select 1 from public.earnings_ledger where source_type='referral_reward' and source_id=commission.id) then raise exception 'Referral issued spendable funds before settlement fraud review'; end if;
end $test$;
select 'PASS: fee rejected; full amount activates once; settlement replay idempotent; premium provisional reward is 20 ETB pending' as result;
rollback;
