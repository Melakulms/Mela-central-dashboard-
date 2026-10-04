-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260827142130
create or replace function public.handle_new_auth_user_invitation() returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  perform public.ensure_referral_code(new.id);
  perform public.process_registration_invitation(new.id, new.raw_user_meta_data->>'invitation_code');
  return new;
end;
$function$;
;
