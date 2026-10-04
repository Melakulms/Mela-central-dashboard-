-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816233748
create table if not exists private.mela_qa_gate_v36(
  gate_key text primary key,
  allowed_until timestamptz not null,
  consumed_at timestamptz
);
insert into private.mela_qa_gate_v36(gate_key,allowed_until,consumed_at)
values('integration-v36',now()+interval '10 minutes',null)
on conflict(gate_key) do update set allowed_until=excluded.allowed_until,consumed_at=null;

create or replace function public.consume_mela_qa_gate_v36()
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_ok boolean:=false;
begin
  update private.mela_qa_gate_v36
     set consumed_at=now()
   where gate_key='integration-v36' and consumed_at is null and allowed_until>now()
   returning true into v_ok;
  return coalesce(v_ok,false);
end;
$$;
revoke all on function public.consume_mela_qa_gate_v36() from public,anon,authenticated;
grant execute on function public.consume_mela_qa_gate_v36() to service_role;
;
