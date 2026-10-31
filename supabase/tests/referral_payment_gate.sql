begin;
do $test$
declare
 inviter uuid := gen_random_uuid();
 invitee uuid := gen_random_uuid();
 code_value text;
 first_commission public.invitation_commissions;
 repeated public.invitation_commissions;
 blocked boolean := false;
begin
 update public.referral_program_config set enabled=true,free_commission_amount=20,premium_commission_amount=40,currency='ETB' where id=true;
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
 values(inviter,inviter::text||'@example.invalid','{"provider":"email"}','{"full_name":"Referral gate test inviter","role":"student"}',now(),now(),now());
 select code into code_value from public.referral_codes where owner_user_id=inviter and active limit 1;
 if code_value is null then
   code_value := 'TEST-'||replace(inviter::text,'-','');
   insert into public.referral_codes(owner_user_id,code) values(inviter,code_value);
 end if;
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
 values(invitee,invitee::text||'@example.invalid','{"provider":"email"}',jsonb_build_object('full_name','Referral gate test invitee','role','student','invitation_code',code_value),now(),now(),now());
 if (select count(*) from public.registration_referrals where registered_user_id=invitee)<>1 then
   raise exception 'Registration did not preserve invitation attribution';
 end if;
 if exists(select 1 from public.invitation_commissions where registered_user_id=invitee) then
   raise exception 'Signup issued any pre-payment commission';
 end if;
 if exists(select 1 from public.earnings_ledger where user_id=inviter and source_type='referral_reward') then
   raise exception 'Signup credited withdrawable reward';
 end if;
 perform public.process_registration_invitation(invitee,code_value);
 if (select count(*) from public.registration_referrals where registered_user_id=invitee)<>1 then
   raise exception 'Repeated attribution created duplicate';
 end if;
 perform public.process_registration_invitation(inviter,code_value);
 if exists(select 1 from public.invitation_commissions where registered_user_id=inviter and inviter_user_id=inviter) then raise exception 'Self referral accepted'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',invitee)::text,true);
 execute 'set local role authenticated';
 begin
   perform public.process_registration_invitation(invitee,code_value);
 exception when insufficient_privilege then blocked:=true;
 end;
 if not blocked then raise exception 'Authenticated caller could issue referral commission'; end if;
 execute 'reset role';
end $test$;
select 'PASS: attribution once; no signup reward; self referral denied; client execution denied' as result;
rollback;
