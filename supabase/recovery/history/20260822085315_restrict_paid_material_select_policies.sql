-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822085315
drop policy if exists mela_learning_materials_anon_read on public.mela_learning_materials;
drop policy if exists mela_learning_materials_authenticated_read on public.mela_learning_materials;
drop policy if exists mela_learning_chapter_materials_anon_read on public.mela_learning_chapter_materials;
drop policy if exists mela_learning_chapter_materials_authenticated_read on public.mela_learning_chapter_materials;
create policy mela_learning_materials_anon_read on public.mela_learning_materials for select to anon using (status = 'published' and access_tier = 'free');
create policy mela_learning_materials_authenticated_read on public.mela_learning_materials for select to authenticated using (
 private.is_admin_user() or (
  status = 'published' and (
   access_tier = 'free'
   or (access_tier = 'subscription' and exists (
    select 1 from public.mela_user_learning_entitlements e join public.mela_learning_products p on p.product_key = e.product_key
    where e.user_id = auth.uid() and e.status = 'active' and p.product_type in ('subscription','institution') and e.starts_at <= now() and (e.ends_at is null or e.ends_at > now())
   ))
   or (access_tier = 'one_time' and exists (
    select 1 from public.mela_user_learning_entitlements e
    where e.user_id = auth.uid() and e.status = 'active' and e.product_key = mela_learning_materials.product_key and e.starts_at <= now() and (e.ends_at is null or e.ends_at > now())
   ))
  )
 )
);
create policy mela_learning_chapter_materials_anon_read on public.mela_learning_chapter_materials for select to anon using (status = 'published' and access_tier = 'free');
create policy mela_learning_chapter_materials_authenticated_read on public.mela_learning_chapter_materials for select to authenticated using (
 private.is_admin_user() or (
  status = 'published' and (
   access_tier = 'free'
   or (access_tier = 'subscription' and exists (
    select 1 from public.mela_user_learning_entitlements e join public.mela_learning_products p on p.product_key = e.product_key
    where e.user_id = auth.uid() and e.status = 'active' and p.product_type in ('subscription','institution') and e.starts_at <= now() and (e.ends_at is null or e.ends_at > now())
   ))
   or (access_tier = 'one_time' and exists (
    select 1 from public.mela_user_learning_entitlements e
    where e.user_id = auth.uid() and e.status = 'active' and e.product_key = mela_learning_chapter_materials.product_key and e.starts_at <= now() and (e.ends_at is null or e.ends_at > now())
   ))
  )
 )
);
;
