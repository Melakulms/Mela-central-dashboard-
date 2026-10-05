set lock_timeout='5s';
create or replace function public.guard_learning_payment_attempt()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_price integer;
 v_currency text;
 trusted boolean := coalesce((select auth.jwt()->>'role')='service_role',false)
   or (session_user in ('postgres','service_role','supabase_auth_admin')
       and coalesce(current_setting('role',true),'none') in ('none','postgres','service_role','supabase_auth_admin')
       and (select auth.uid()) is null);
begin
 if tg_op='INSERT' then
  if not trusted and new.user_id is distinct from (select auth.uid()) then raise exception 'user mismatch'; end if;
  select active_price_minor,currency into v_price,v_currency from public.mela_learning_products
   where product_key=new.product_key and active=true and sale_enabled=true;
  if v_price is null then raise exception 'product unavailable for checkout'; end if;
  new.expected_amount_minor:=v_price; new.expected_currency:=v_currency; new.provider:='chapa'; new.status:='initiated';
  new.provider_status:=null; new.provider_ref:=null; new.provider_method:=null; new.provider_type:=null;
  new.provider_charge:=null; new.verify_payload:='{}'::jsonb; new.entitlement_id:=null; new.paid_at:=null;
  new.last_verified_at:=null; new.failure_reason:=null;
 elsif tg_op='UPDATE' then
  if new.id is distinct from old.id or new.user_id is distinct from old.user_id
    or new.product_key is distinct from old.product_key or new.provider is distinct from old.provider
    or new.tx_ref is distinct from old.tx_ref or new.expected_amount_minor is distinct from old.expected_amount_minor
    or new.expected_currency is distinct from old.expected_currency or new.mode is distinct from old.mode
  then raise exception 'payment identity fields are immutable'; end if;
  if not trusted then raise insufficient_privilege using message='Payment updates require a trusted backend'; end if;
  if old.status not in ('initiated','pending') then return old; end if;
 end if;
 return new;
end;
$$;
revoke execute on function public.guard_learning_payment_attempt() from public,anon,authenticated;
