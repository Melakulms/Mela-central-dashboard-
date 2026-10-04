-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809155049
alter type public.app_language add value if not exists 'ti';
alter type public.app_language add value if not exists 'so';

create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare pref text;
begin
  pref := coalesce(new.raw_user_meta_data ->> 'language_pref','en');
  if pref not in ('en','am','om','ti','so') then pref := 'en'; end if;
  insert into public.profiles (id, full_name, language_pref)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(split_part(coalesce(new.email,''), '@', 1), ''), 'Mela Learner'),
    pref::public.app_language
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_auth_user() from public;
revoke all on function private.handle_new_auth_user() from anon;
revoke all on function private.handle_new_auth_user() from authenticated;
;
