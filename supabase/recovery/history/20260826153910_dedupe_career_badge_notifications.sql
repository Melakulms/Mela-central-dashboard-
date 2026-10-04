-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826153910
DELETE FROM public.notifications n USING public.notifications older WHERE n.user_id=older.user_id AND n.title=older.title AND n.body IS NOT DISTINCT FROM older.body AND n.ref_table IS NOT DISTINCT FROM older.ref_table AND n.ref_id IS NOT DISTINCT FROM older.ref_id AND n.created_at=older.created_at AND n.id>older.id; CREATE UNIQUE INDEX IF NOT EXISTS notifications_user_ref_dedupe_idx ON public.notifications (user_id,title,md5(coalesce(body,'')),ref_table,ref_id) WHERE ref_id IS NOT NULL;
;
