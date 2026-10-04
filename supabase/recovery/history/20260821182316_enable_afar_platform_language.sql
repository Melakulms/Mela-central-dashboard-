-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821182316
alter table public.platform_languages drop constraint if exists platform_languages_code_chk;
alter table public.platform_languages add constraint platform_languages_code_chk check (language_code = any (array['en'::text,'am'::text,'om'::text,'ti'::text,'so'::text,'aa'::text]));
insert into public.platform_languages(language_code,language_name,native_name,enabled,text_direction,sort_order) values('aa','Afar','Qafar af',true,'ltr',6) on conflict(language_code) do update set language_name=excluded.language_name,native_name=excluded.native_name,enabled=true,text_direction=excluded.text_direction,sort_order=excluded.sort_order,updated_at=now();
;
