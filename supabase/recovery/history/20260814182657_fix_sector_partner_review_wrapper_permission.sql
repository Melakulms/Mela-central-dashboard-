-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814182657
grant execute on function private.process_sector_partner_registration(uuid,text,text) to authenticated;
;
