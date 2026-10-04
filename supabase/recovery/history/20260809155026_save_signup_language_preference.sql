-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809155026
create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  pref text;
  lang public.app_language;
begin
  pref := coalesce(new.raw_user_meta_data ->> 'language_pref', 'en');
  lang := case pref
    when 'am' then 'am'::public.app_language
    when 'om' then 'om'::public.app_language
    when 'ti' then 'ti'::public.app_language
    when 'so' then 'so'::public.app_language
    else 'en'::public.app_language
  end;
  insert into public.profiles (id, full_name, language_pref)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(split_part(coalesce(new.email,''), '@', 1), ''), 'Mela Learner'),
    lang
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_auth_user() from public;
revoke all on function private.handle_new_auth_user() from anon;
revoke all on function private.handle_new_auth_user() from authenticated;
;
