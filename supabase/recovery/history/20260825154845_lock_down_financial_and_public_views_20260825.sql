-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825154845
begin;

-- Financial history must be read-only from the client.
revoke insert, update, delete on table public.my_payment_history from anon, authenticated;

-- Public learning-content views are intentionally readable, but must never be client-writable.
revoke insert, update, delete on table public.mela_learning_chapter_material_content_public from anon, authenticated;
revoke insert, update, delete on table public.mela_learning_material_content_public from anon, authenticated;

grant select on table public.mela_learning_chapter_material_content_public to anon, authenticated;
grant select on table public.mela_learning_material_content_public to anon, authenticated;

commit;
;
