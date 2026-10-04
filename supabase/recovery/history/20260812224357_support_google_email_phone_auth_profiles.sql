-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812224357
alter table public.profiles alter column email drop not null;

alter table public.profiles add column if not exists auth_primary_method text;
alter table public.profiles add column if not exists auth_provider text;
alter table public.profiles add column if not exists email_verified boolean not null default false;
alter table public.profiles add column if not exists phone_verified boolean not null default false;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text;
  v_name text;
  v_avatar text;
begin
  v_provider := coalesce(
    nullif(new.raw_app_meta_data ->> 'provider',''),
    case when new.phone is not null then 'phone' when new.email is not null then 'email' else 'unknown' end
  );
  v_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'full_name',''),
    nullif(new.raw_user_meta_data ->> 'name',''),
    nullif(split_part(coalesce(new.email,''),'@',1),''),
    case when new.phone is not null then 'Mela User ' || right(new.phone,4) end,
    'Mela User'
  );
  v_avatar := coalesce(
    nullif(new.raw_user_meta_data ->> 'avatar_url',''),
    nullif(new.raw_user_meta_data ->> 'picture','')
  );

  insert into public.profiles (
    id, full_name, email, phone_number, avatar_url, preferred_language,
    auth_primary_method, auth_provider, email_verified, phone_verified
  ) values (
    new.id,
    v_name,
    nullif(new.email,''),
    nullif(new.phone,''),
    v_avatar,
    coalesce(nullif(new.raw_user_meta_data ->> 'preferred_language',''), nullif(new.raw_user_meta_data ->> 'language',''), 'English'),
    case when v_provider='phone' then 'phone' when v_provider='google' then 'google' else 'email' end,
    v_provider,
    new.email_confirmed_at is not null,
    new.phone_confirmed_at is not null
  )
  on conflict (id) do update set
    full_name=coalesce(nullif(public.profiles.full_name,''), excluded.full_name),
    email=coalesce(excluded.email, public.profiles.email),
    phone_number=coalesce(excluded.phone_number, public.profiles.phone_number),
    avatar_url=coalesce(public.profiles.avatar_url, excluded.avatar_url),
    preferred_language=coalesce(public.profiles.preferred_language, excluded.preferred_language),
    auth_primary_method=coalesce(public.profiles.auth_primary_method, excluded.auth_primary_method),
    auth_provider=coalesce(excluded.auth_provider, public.profiles.auth_provider),
    email_verified=(public.profiles.email_verified or excluded.email_verified),
    phone_verified=(public.profiles.phone_verified or excluded.phone_verified),
    updated_at=now();

  insert into public.notification_preferences(user_id)
  values(new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function private.sync_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text;
begin
  v_provider := coalesce(nullif(new.raw_app_meta_data ->> 'provider',''), case when new.phone is not null then 'phone' when new.email is not null then 'email' else 'unknown' end);
  update public.profiles
  set email = nullif(new.email,''),
      phone_number = nullif(new.phone,''),
      full_name = coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''), nullif(new.raw_user_meta_data ->> 'name',''), public.profiles.full_name),
      avatar_url = coalesce(public.profiles.avatar_url, nullif(new.raw_user_meta_data ->> 'avatar_url',''), nullif(new.raw_user_meta_data ->> 'picture','')),
      auth_provider = v_provider,
      email_verified = new.email_confirmed_at is not null,
      phone_verified = new.phone_confirmed_at is not null,
      updated_at = now()
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_profile_sync on auth.users;
create trigger on_auth_user_profile_sync
after update of email, phone, email_confirmed_at, phone_confirmed_at, raw_user_meta_data, raw_app_meta_data on auth.users
for each row execute function private.sync_auth_user_profile();

;
