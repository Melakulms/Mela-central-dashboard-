-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812222258
create or replace function private.protect_sponsored_challenge_fields()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  if current_user='authenticated' and (select auth.uid()) is not null and not private.is_admin_user() then
    if new.sponsor_employer_id is distinct from old.sponsor_employer_id
      or new.created_by is distinct from old.created_by
      or new.status is distinct from old.status
      or new.published_at is distinct from old.published_at
      or new.winner_submission_id is distinct from old.winner_submission_id then
      raise exception 'challenge ownership and lifecycle fields are server managed';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end $$;
;
