-- Harden employer and opportunity administrative review transitions.
-- These database guards complement the Edge Function and protect against
-- stale/concurrent clients or direct privileged writes.

create or replace function public.guard_employer_registration_review()
returns trigger
language plpgsql
as $$
declare
  current_status text := coalesce(old.status::text, '');
  next_status text := coalesce(new.status::text, '');
  reason text := nullif(btrim(coalesce(new.review_notes, '')), '');
begin
  if next_status in ('approved', 'rejected') and reason is null then
    raise exception using
      errcode = '23514',
      message = 'A review reason is required when approving or rejecting an employer registration';
  end if;

  if next_status <> current_status and not (
    (current_status = 'pending' and next_status in ('review', 'approved', 'rejected')) or
    (current_status = 'review' and next_status in ('approved', 'rejected', 'pending')) or
    (current_status = 'review_required' and next_status in ('review', 'approved', 'rejected'))
  ) then
    raise exception using
      errcode = '23514',
      message = format('Invalid employer registration status transition: %s -> %s', current_status, next_status);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_employer_registration_review on public.employer_registration_requests;
create trigger trg_guard_employer_registration_review
before update of status, review_notes on public.employer_registration_requests
for each row execute function public.guard_employer_registration_review();

create or replace function public.guard_opportunity_review()
returns trigger
language plpgsql
as $$
declare
  current_status text := coalesce(old.moderation_status::text, 'pending');
  next_status text := coalesce(new.moderation_status::text, 'pending');
  reason text := nullif(btrim(coalesce(new.moderation_notes, '')), '');
begin
  if next_status in ('approved', 'rejected') and reason is null then
    raise exception using
      errcode = '23514',
      message = 'A moderation reason is required when approving or rejecting an opportunity';
  end if;

  if next_status <> current_status and not (
    (current_status = 'pending' and next_status in ('approved', 'rejected', 'flagged')) or
    (current_status = 'flagged' and next_status in ('pending', 'approved', 'rejected')) or
    (current_status = 'rejected' and next_status = 'pending') or
    (current_status = 'approved' and next_status = 'flagged')
  ) then
    raise exception using
      errcode = '23514',
      message = format('Invalid opportunity moderation transition: %s -> %s', current_status, next_status);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_opportunity_review on public.opportunities;
create trigger trg_guard_opportunity_review
before update of moderation_status, moderation_notes on public.opportunities
for each row execute function public.guard_opportunity_review();

comment on function public.guard_employer_registration_review() is
  'Database-level state-machine and review-reason guard for employer registrations.';
comment on function public.guard_opportunity_review() is
  'Database-level state-machine and review-reason guard for opportunity moderation.';
