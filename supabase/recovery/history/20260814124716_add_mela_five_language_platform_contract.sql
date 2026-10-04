-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814124716
create table if not exists public.platform_languages (
  language_code text primary key,
  language_name text not null unique,
  native_name text not null,
  enabled boolean not null default true,
  text_direction text not null default 'ltr' check (text_direction in ('ltr','rtl')),
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_languages_code_chk check (language_code in ('en','am','om','ti','so'))
);
alter table public.platform_languages enable row level security;
revoke all on table public.platform_languages from public,anon,authenticated;
grant select on table public.platform_languages to anon,authenticated,service_role;
grant insert,update,delete on table public.platform_languages to service_role;
drop policy if exists platform_languages_read_enabled on public.platform_languages;
create policy platform_languages_read_enabled on public.platform_languages for select to anon,authenticated using (enabled=true);

insert into public.platform_languages(language_code,language_name,native_name,enabled,text_direction,sort_order)
values
 ('en','English','English',true,'ltr',1),
 ('am','Amharic','አማርኛ',true,'ltr',2),
 ('om','Afaan Oromo','Afaan Oromoo',true,'ltr',3),
 ('ti','Tigrinya','ትግርኛ',true,'ltr',4),
 ('so','Somali','Soomaali',true,'ltr',5)
on conflict (language_code) do update set language_name=excluded.language_name,native_name=excluded.native_name,enabled=excluded.enabled,text_direction=excluded.text_direction,sort_order=excluded.sort_order,updated_at=now();

update public.profiles
set preferred_language='English'
where preferred_language is null or preferred_language not in ('English','Amharic','Afaan Oromo','Tigrinya','Somali');

alter table public.profiles drop constraint if exists profiles_preferred_language_chk;
alter table public.profiles add constraint profiles_preferred_language_chk check (preferred_language in ('English','Amharic','Afaan Oromo','Tigrinya','Somali'));

create or replace function public.set_my_preferred_language(p_language text)
returns text
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_language text := nullif(trim(coalesce(p_language,'')),'');
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_language not in ('English','Amharic','Afaan Oromo','Tigrinya','Somali') then
    raise exception 'unsupported language';
  end if;
  update public.profiles
  set preferred_language=v_language
  where id=v_uid;
  if not found then raise exception 'profile not found'; end if;
  return v_language;
end;
$function$;
revoke all on function public.set_my_preferred_language(text) from public,anon;
grant execute on function public.set_my_preferred_language(text) to authenticated,service_role;

create table if not exists public.platform_translation_cache (
  id uuid primary key default gen_random_uuid(),
  source_hash text not null,
  source_language text not null default 'en' check (source_language in ('en','am','om','ti','so')),
  target_language text not null check (target_language in ('en','am','om','ti','so')),
  source_text text not null,
  translated_text text not null,
  model text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_hash,target_language)
);
create index if not exists platform_translation_cache_target_hash_idx on public.platform_translation_cache(target_language,source_hash);
alter table public.platform_translation_cache enable row level security;
revoke all on table public.platform_translation_cache from public,anon,authenticated;
grant select,insert,update,delete on table public.platform_translation_cache to service_role;

create table if not exists public.platform_translation_glossary (
  id uuid primary key default gen_random_uuid(),
  source_term text not null,
  language_code text not null references public.platform_languages(language_code) on update cascade on delete restrict,
  preferred_translation text not null,
  preserve_exact boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_term,language_code)
);
alter table public.platform_translation_glossary enable row level security;
revoke all on table public.platform_translation_glossary from public,anon,authenticated;
grant select on table public.platform_translation_glossary to authenticated,service_role;
grant insert,update,delete on table public.platform_translation_glossary to service_role;
drop policy if exists translation_glossary_authenticated_read on public.platform_translation_glossary;
create policy translation_glossary_authenticated_read on public.platform_translation_glossary for select to authenticated using (true);

insert into public.platform_translation_glossary(source_term,language_code,preferred_translation,preserve_exact,notes)
select t.term,l.language_code,case when t.preserve then t.term else t.term end,t.preserve,'Mela protected product term'
from (values ('Mela',true),('Career Passport',true),('Mela Arena',true),('ETB',true),('TVET',true),('AI',true)) as t(term,preserve)
cross join public.platform_languages l
on conflict (source_term,language_code) do nothing;
;
