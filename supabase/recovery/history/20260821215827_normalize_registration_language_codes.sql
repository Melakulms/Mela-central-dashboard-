-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821215827
CREATE OR REPLACE FUNCTION private.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_provider text;
  v_name text;
  v_avatar text;
  v_lang text;
begin
  if not public.platform_feature_available('registrations') then
    raise exception 'Mela registrations are temporarily disabled by the platform administrator.' using errcode='P0001';
  end if;

  v_provider := coalesce(nullif(new.raw_app_meta_data ->> 'provider',''), case when new.phone is not null then 'phone' when new.email is not null then 'email' else 'unknown' end);
  v_name := coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''), nullif(new.raw_user_meta_data ->> 'name',''), nullif(split_part(coalesce(new.email,''),'@',1),''), case when new.phone is not null then 'Mela User ' || right(new.phone,4) end, 'Mela User');
  v_avatar := coalesce(nullif(new.raw_user_meta_data ->> 'avatar_url',''), nullif(new.raw_user_meta_data ->> 'picture',''));
  v_lang := lower(coalesce(nullif(new.raw_user_meta_data ->> 'preferred_language',''), nullif(new.raw_user_meta_data ->> 'language',''), 'en'));
  v_lang := case v_lang when 'english' then 'en' when 'amharic' then 'am' when 'oromo' then 'om' when 'afaan oromo' then 'om' when 'tigrinya' then 'ti' when 'somali' then 'so' when 'or' then 'om' else v_lang end;
  if not exists(select 1 from public.platform_languages l where l.language_code=v_lang and l.enabled) then v_lang := 'en'; end if;

  insert into public.profiles (id, full_name, email, phone_number, avatar_url, preferred_language, auth_primary_method, auth_provider, email_verified, phone_verified)
  values (new.id, v_name, nullif(new.email,''), nullif(new.phone,''), v_avatar, v_lang, case when v_provider='phone' then 'phone' when v_provider='google' then 'google' else 'email' end, v_provider, (nullif(new.email,'') is not null and new.email_confirmed_at is not null), (nullif(new.phone,'') is not null and new.phone_confirmed_at is not null))
  on conflict (id) do update set
    full_name=coalesce(nullif(public.profiles.full_name,''), excluded.full_name), email=coalesce(excluded.email, public.profiles.email), phone_number=coalesce(excluded.phone_number, public.profiles.phone_number), avatar_url=coalesce(public.profiles.avatar_url, excluded.avatar_url), preferred_language=coalesce(public.profiles.preferred_language, excluded.preferred_language), auth_primary_method=coalesce(public.profiles.auth_primary_method, excluded.auth_primary_method), auth_provider=coalesce(excluded.auth_provider, public.profiles.auth_provider), email_verified=(public.profiles.email_verified or excluded.email_verified), phone_verified=(public.profiles.phone_verified or excluded.phone_verified), updated_at=now();

  insert into public.notification_preferences(user_id) values(new.id) on conflict (user_id) do nothing;
  return new;
end;
$function$;
;
