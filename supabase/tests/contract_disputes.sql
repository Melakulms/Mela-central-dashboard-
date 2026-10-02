begin;
do $test$
declare
  learner uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); task uuid; employer uuid; contract uuid; result public.freelance_contracts; blocked boolean:=false;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  select u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Dispute rollback test","role":"student"}',now(),now(),now() from unnest(array[learner,outsider]) u;
  update auth.users set email_confirmed_at=now() where id in (learner,outsider);
  insert into public.employers(company_name) values('Rollback dispute employer') returning id into employer;
  insert into public.marketplace_tasks(title,status,employer_id) values('Rollback dispute fixture','assigned',employer) returning id into task;
  insert into public.freelance_contracts(task_id,employer_id,freelancer_id,agreed_amount,status) values(task,employer,learner,100,'active') returning id into contract;
  insert into public.escrow_transactions(task_id,user_id,contract_id,amount_minor,status) values(task,learner,contract,10000,'held');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  begin perform public.raise_contract_dispute(contract,'Unauthorized test request'); exception when others then blocked:=true; end;
  if not blocked then raise exception 'outsider disputed another user contract'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',learner,'role','authenticated')::text,true);
  result:=public.raise_contract_dispute(contract,'The deliverable was not reviewed fairly.');
  if result.status<>'disputed' then raise exception 'contract was not placed on hold'; end if;
  if not exists(select 1 from public.escrow_transactions where contract_id=contract and status='disputed') then raise exception 'escrow was not frozen'; end if;
  perform public.raise_contract_dispute(contract,'Retry after a connection interruption.');
  execute 'reset role';
  if (select count(*) from public.reports where target_id=contract and reason='contract_dispute')<>1 then raise exception 'dispute retry created duplicate reports'; end if;
end $test$;
rollback;
select 'PASS: participant dispute, escrow hold, outsider denial, retry idempotency; all fixtures rolled back' as regression_result;
