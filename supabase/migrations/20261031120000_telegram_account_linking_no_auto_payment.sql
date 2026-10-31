-- Short-lived account-link codes connect a Telegram private chat to a signed-in MELA account.
-- No bot chat is trusted as an MELA identity until explicit one-time linking.
create table if not exists mela_billing.telegram_link_codes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 code_digest text not null unique,
 expires_at timestamptz not null,
 used_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists mela_billing.telegram_links (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 chat_id text not null unique,
 linked_at timestamptz not null default now()
);
create index if not exists mela_billing_telegram_link_codes_user
 on mela_billing.telegram_link_codes(user_id,expires_at desc);
alter table mela_billing.telegram_link_codes enable row level security;
alter table mela_billing.telegram_links enable row level security;
revoke all on mela_billing.telegram_link_codes,mela_billing.telegram_links from public,anon,authenticated;

create or replace function public.mela_billing_link_code_v1()
returns text language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid(); v_code text;
begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 or not exists(select 1 from public.profiles where id=u and deleted_at is null)
 or not exists(select 1 from auth.users where id=u and email_confirmed_at is not null)
 then raise exception 'Verified MELA login required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('mela-telegram-link:'||u::text,0));
 update mela_billing.telegram_link_codes set used_at=now()
   where user_id=u and used_at is null;
 v_code:=upper(replace(pg_catalog.gen_random_uuid()::text,'-',''));
 insert into mela_billing.telegram_link_codes(user_id,code_digest,expires_at)
 values(u,md5(v_code),now()+interval '5 minutes');
 return v_code;
end $$;
revoke all on function public.mela_billing_link_code_v1() from public,anon;
grant execute on function public.mela_billing_link_code_v1() to authenticated;

create or replace function public.mela_billing_bot_v1(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_chat text:=p_data->>'chat_id'; v_code mela_billing.telegram_link_codes;
 v_owner uuid; v_link mela_billing.telegram_links;
begin
 if v_chat is null or v_chat !~ '^[0-9]{1,20}$'
 then raise exception 'Invalid Telegram chat'; end if;
 if p_action='plans' then
   return jsonb_build_object('open',(select submissions_enabled from mela_billing.settings where singleton=true),
    'plans',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'amount_etb',price_minor/100,
       'commission_etb',case when plan_key='pro_monthly' then 20 else 40 end)
       order by price_minor),'[]'::jsonb) from public.subscription_plans
       where active and plan_key in ('pro_monthly','premium_monthly')));
 elsif p_action='link' then
   if (p_data->>'code') !~ '^[A-F0-9]{32}$'
   then return jsonb_build_object('linked',false,'reason','invalid_or_expired_code'); end if;
   select * into v_code from mela_billing.telegram_link_codes
    where code_digest=md5(p_data->>'code') and expires_at>now() and used_at is null
    for update;
   if v_code.id is null then
     return jsonb_build_object('linked',false,'reason','invalid_or_expired_code'); end if;
   v_owner:=v_code.user_id;
   if exists(select 1 from mela_billing.telegram_links
     where chat_id=v_chat and user_id<>v_owner)
   then return jsonb_build_object('linked',false,'reason','chat_already_linked'); end if;
   insert into mela_billing.telegram_links(user_id,chat_id)
      values(v_owner,v_chat)
      on conflict (user_id) do update set chat_id=excluded.chat_id, linked_at=now();
   update mela_billing.telegram_link_codes set used_at=now() where id=v_code.id;
   return jsonb_build_object('linked',true);
 elsif p_action='status' then
   select * into v_link from mela_billing.telegram_links where chat_id=v_chat;
   if v_link.user_id is null then return jsonb_build_object('linked',false,'orders','[]'::jsonb); end if;
   return jsonb_build_object('linked',true,'orders',
     coalesce((select jsonb_agg(x) from
       (select plan_key,amount_minor,status,created_at
        from mela_billing.orders where user_id=v_link.user_id
        order by created_at desc limit 5)x),'[]'::jsonb));
 elsif p_action='unlink' then
   delete from mela_billing.telegram_links where chat_id=v_chat;
   return jsonb_build_object('linked',false);
 else raise exception 'Unknown action'; end if;
end $$;
revoke all on function public.mela_billing_bot_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.mela_billing_bot_v1(text,jsonb) to service_role;
comment on function public.mela_billing_bot_v1(text,jsonb)
 is 'Service-key-only Telegram private-chat linking and read-only order status. Never activates a subscription.';

-- Stronger duplicate protection against already verified receipts in other MELA paths
-- is applied in a separate audited reviewer-function revision.
