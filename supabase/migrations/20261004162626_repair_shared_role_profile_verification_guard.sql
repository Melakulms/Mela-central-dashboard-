create or replace function public.guard_role_profile_verification_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if not private.is_admin_user() then
    if tg_table_name = 'company_profiles' then
      new.verification_status := old.verification_status;
      new.verified_by := old.verified_by;
      new.verified_at := old.verified_at;
    elsif tg_table_name = 'teacher_profiles' then
      new.verification_status := old.verification_status;
      new.verified_by := old.verified_by;
      new.verified_at := old.verified_at;
      new.content_creator_status := old.content_creator_status;
    elsif tg_table_name = 'mentor_profiles' then
      new.verified := old.verified;
      new.verified_by := old.verified_by;
      new.verified_at := old.verified_at;
    elsif tg_table_name = 'educator_profiles' then
      new.verified := old.verified;
      new.verified_by := old.verified_by;
      new.verified_at := old.verified_at;
    end if;
  end if;
  return new;
end;
$function$;
