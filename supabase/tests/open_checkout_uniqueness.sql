begin;
do $test$
declare
 actor uuid:=gen_random_uuid();
 course uuid;
 product text;
 ref text:=gen_random_uuid()::text;
 blocked boolean;
begin
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 values(actor,actor::text||'@example.invalid','{"provider":"email"}','{"role":"student","full_name":"Checkout uniqueness test"}',now(),now());
 select id into course from public.courses limit 1;
 select product_key into product from public.mela_learning_products where product_type='subscription' limit 1;
 if course is null or product is null then raise exception 'Test requires existing course and product'; end if;
 insert into public.payments(user_id,course_id,mode,tx_ref,expected_amount_cents,expected_currency,status)
 values(actor,course,'test',ref||'-course',2000,'ETB','initiated');
 blocked:=false;
 begin
  insert into public.payments(user_id,course_id,mode,tx_ref,expected_amount_cents,expected_currency,status)
  values(actor,course,'test',ref||'-course-duplicate',2000,'ETB','pending');
 exception when unique_violation then blocked:=true;
 end;
 if not blocked then raise exception 'Duplicate open course checkout allowed'; end if;
 update public.payments set status='failed' where tx_ref=ref||'-course';
 insert into public.payments(user_id,course_id,mode,tx_ref,expected_amount_cents,expected_currency,status)
 values(actor,course,'test',ref||'-course-retry',2000,'ETB','initiated');
 update public.mela_learning_products set active=true,sale_enabled=true,active_price_minor=5000,currency='ETB' where product_key=product;
 insert into public.mela_learning_payment_attempts(user_id,product_key,mode,tx_ref,expected_amount_minor,expected_currency,status)
 values(actor,product,'test',ref||'-learning',5000,'ETB','initiated');
 blocked:=false;
 begin
  insert into public.mela_learning_payment_attempts(user_id,product_key,mode,tx_ref,expected_amount_minor,expected_currency,status)
  values(actor,product,'test',ref||'-learning-duplicate',5000,'ETB','pending');
 exception when unique_violation then blocked:=true;
 end;
 if not blocked then raise exception 'Duplicate open learning checkout allowed'; end if;
 if not exists(select 1 from pg_index where indexrelid='public.escrow_one_open_checkout_uidx'::regclass and indisunique and indisvalid) then raise exception 'Escrow duplicate prevention index invalid'; end if;
end $test$;
select 'PASS: duplicate course/learning attempts rejected; confirmed failed checkout can retry; escrow unique index valid' as result;
rollback;
