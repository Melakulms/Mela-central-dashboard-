-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822092738
revoke insert,update,delete on public.mela_learning_products from authenticated;
;
