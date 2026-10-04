-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821232552
revoke execute on function public.request_sector_partner_registration(text,text,text,text,text) from anon;
revoke execute on function public.request_sector_partner_registration(text,text,text,text,text) from public;
grant execute on function public.request_sector_partner_registration(text,text,text,text,text) to authenticated;
;
