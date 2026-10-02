-- Non-destructive privilege/index assertions for final launch boundaries.
do $test$
begin
  if has_table_privilege('authenticated','public.assessment_attempts','UPDATE') then
    raise exception 'authenticated must not update assessment_attempts directly';
  end if;
  if not has_table_privilege('authenticated','public.assessment_attempts','SELECT')
     or not has_table_privilege('authenticated','public.assessment_attempts','INSERT') then
    raise exception 'authenticated must retain assessment SELECT/INSERT';
  end if;
  if not has_function_privilege('authenticated','public.submit_my_assessment_attempt(uuid)','EXECUTE') then
    raise exception 'authenticated submit RPC execute is required';
  end if;
  if has_table_privilege('authenticated','public.mela_learning_payment_attempts','INSERT') then
    raise exception 'browser users must not insert learning payment attempts';
  end if;
  if not has_table_privilege('authenticated','public.mela_learning_payment_attempts','SELECT') then
    raise exception 'users must retain read access to their payment history';
  end if;
  if not exists(select 1 from pg_indexes where schemaname='public' and indexname='escrow_payment_success_provider_ref_uidx')
     or not exists(select 1 from pg_indexes where schemaname='public' and indexname='learning_payment_success_provider_ref_uidx')
     or not exists(select 1 from pg_indexes where schemaname='public' and indexname='payout_success_provider_ref_uidx') then
    raise exception 'successful provider-reference uniqueness indexes are missing';
  end if;
  if has_function_privilege('authenticated','public.finalize_escrow_payment(uuid,text,text,text,numeric,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.record_milestone_payout(uuid,text,text)','EXECUTE') then
    raise exception 'financial finalizers must not be browser executable';
  end if;
end $test$;
select 'PASS: assessment RPC-only and finance service-only boundaries' as result;
