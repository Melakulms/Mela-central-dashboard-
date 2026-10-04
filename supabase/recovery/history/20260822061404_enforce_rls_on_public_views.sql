-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822061404
alter view public.mela_learning_chapter_material_content_public set (security_invoker = true); alter view public.mela_learning_material_content_public set (security_invoker = true); alter view public.my_payment_history set (security_invoker = true);
;
