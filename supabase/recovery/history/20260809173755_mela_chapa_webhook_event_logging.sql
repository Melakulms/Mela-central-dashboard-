-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809173755
create or replace function public.log_chapa_webhook_event(
  p_signature text,
  p_tx_ref text,
  p_payload jsonb
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.payment_webhook_events(provider, signature, tx_ref, payload)
  values ('chapa', p_signature, p_tx_ref, p_payload)
  on conflict (provider, signature) do nothing;
  return true;
end;
$$;
revoke all on function public.log_chapa_webhook_event(text,text,jsonb) from public;
revoke all on function public.log_chapa_webhook_event(text,text,jsonb) from anon;
revoke all on function public.log_chapa_webhook_event(text,text,jsonb) from authenticated;
grant execute on function public.log_chapa_webhook_event(text,text,jsonb) to service_role;
;
