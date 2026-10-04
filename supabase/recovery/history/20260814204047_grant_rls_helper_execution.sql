-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204047
grant execute on function private.can_educate_learner(uuid,uuid) to authenticated; grant execute on function private.can_view_classroom(uuid,uuid) to authenticated;
;
