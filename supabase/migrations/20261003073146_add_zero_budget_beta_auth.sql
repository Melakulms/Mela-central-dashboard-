alter table public.profiles add column if not exists username text;

alter table public.profiles drop constraint if exists profiles_username_format_check;
alter table public.profiles add constraint profiles_username_format_check
  check (username is null or (username = lower(username) and username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'));

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username)) where username is not null;

create table if not exists public.beta_access_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  role public.user_role not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  constraint beta_access_invites_role_check check (role in ('student','parent','teacher','company')),
  constraint beta_access_invites_expiry_check check (expires_at > created_at),
  constraint beta_access_invites_note_check check (note is null or length(note) <= 500)
);

create index if not exists beta_access_invites_state_idx
  on public.beta_access_invites (expires_at, used_at, revoked_at);

create table if not exists public.beta_auth_recovery (
  user_id uuid primary key references auth.users(id) on delete cascade,
  recovery_hash text not null,
  rotated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.beta_access_invites enable row level security;
alter table public.beta_auth_recovery enable row level security;

revoke all on table public.beta_access_invites from public, anon, authenticated;
revoke all on table public.beta_auth_recovery from public, anon, authenticated;
grant select, insert, update, delete on table public.beta_access_invites to service_role;
grant select, insert, update, delete on table public.beta_auth_recovery to service_role;

drop policy if exists beta_access_invites_service_only on public.beta_access_invites;
create policy beta_access_invites_service_only on public.beta_access_invites
  for all to service_role using (true) with check (true);

drop policy if exists beta_auth_recovery_service_only on public.beta_auth_recovery;
create policy beta_auth_recovery_service_only on public.beta_auth_recovery
  for all to service_role using (true) with check (true);

create or replace function private.protect_profile_identity_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public','private'
as $function$
begin
  if tg_op='UPDATE' then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.username is distinct from old.username then
      if not private.is_admin_user() then
        raise exception 'Protected profile identity fields cannot be changed by the client';
      end if;
    end if;
  end if;
  return new;
end;
$function$;

insert into public.platform_feature_flags(feature_key,label,description,enabled,maintenance_message,config)
values(
  'beta_access',
  'Invite-only beta access',
  'Zero-budget invite-only beta authentication using usernames and one-time recovery codes.',
  true,
  null,
  '{"mode":"invite_only","public_launch":false,"requires_email":false}'::jsonb
)
on conflict(feature_key) do update set
  label=excluded.label,
  description=excluded.description,
  enabled=excluded.enabled,
  maintenance_message=excluded.maintenance_message,
  config=excluded.config,
  updated_at=now();
