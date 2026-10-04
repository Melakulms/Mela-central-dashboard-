-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260920104721

create or replace function private.create_arena_season(
  p_title text,
  p_slug text,
  p_description text default null,
  p_arena_type text default null,
  p_career_path_id uuid default null,
  p_visibility text default 'public',
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if not private.is_admin_user() then
    raise exception 'admin authorization required';
  end if;
  if nullif(trim(p_title),'') is null or nullif(trim(p_slug),'') is null then
    raise exception 'title and slug required';
  end if;
  if p_visibility not in ('public','private','invite') then
    raise exception 'invalid visibility';
  end if;
  if p_starts_at is not null and p_ends_at is not null and p_ends_at <= p_starts_at then
    raise exception 'season end must be after start';
  end if;
  insert into public.arena_seasons(
    title,slug,description,arena_type,career_path_id,visibility,status,starts_at,ends_at,created_by
  )
  values(
    left(trim(p_title),160),
    lower(regexp_replace(trim(p_slug),'[^a-zA-Z0-9-]+','-','g')),
    left(p_description,4000),
    p_arena_type,
    p_career_path_id,
    p_visibility,
    'draft',
    p_starts_at,
    p_ends_at,
    v_uid
  )
  returning id into v_id;
  return v_id;
end
$function$;

;
