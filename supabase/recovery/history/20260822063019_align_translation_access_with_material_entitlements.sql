-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822063019
drop policy if exists mela_learning_material_translations_read on public.mela_learning_material_translations;
create policy mela_learning_material_translations_read on public.mela_learning_material_translations for select to authenticated using (
  private.is_admin_user() or (
    review_status='certified' and exists (
      select 1 from public.mela_learning_materials m
      where m.id=material_id and m.status='published' and (
        m.access_tier='free'
        or (m.access_tier='subscription' and exists (
          select 1 from public.mela_user_learning_entitlements e
          join public.mela_learning_products p on p.product_key=e.product_key
          where e.user_id=(select auth.uid()) and e.status='active'
            and p.product_type in ('subscription','institution')
            and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
        ))
        or (m.access_tier='one_time' and exists (
          select 1 from public.mela_user_learning_entitlements e
          where e.user_id=(select auth.uid()) and e.status='active'
            and e.product_key=m.product_key and e.starts_at<=now()
            and (e.ends_at is null or e.ends_at>now())
        ))
      )
    )
  )
);
drop policy if exists mela_learning_chapter_translations_anon_read on public.mela_learning_chapter_material_translations;
drop policy if exists mela_learning_chapter_translations_authenticated_read on public.mela_learning_chapter_material_translations;
create policy mela_learning_chapter_translations_anon_read on public.mela_learning_chapter_material_translations for select to anon using (
  review_status='approved' and exists (
    select 1 from public.mela_learning_chapter_materials m
    where m.id=material_id and m.status='published' and m.access_tier='free'
  )
);
create policy mela_learning_chapter_translations_authenticated_read on public.mela_learning_chapter_material_translations for select to authenticated using (
  private.is_admin_user() or (
    review_status='approved' and exists (
      select 1 from public.mela_learning_chapter_materials m
      where m.id=material_id and m.status='published' and (
        m.access_tier='free'
        or (m.access_tier='subscription' and exists (
          select 1 from public.mela_user_learning_entitlements e
          join public.mela_learning_products p on p.product_key=e.product_key
          where e.user_id=(select auth.uid()) and e.status='active'
            and p.product_type in ('subscription','institution')
            and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
        ))
        or (m.access_tier='one_time' and exists (
          select 1 from public.mela_user_learning_entitlements e
          where e.user_id=(select auth.uid()) and e.status='active'
            and e.product_key=m.product_key and e.starts_at<=now()
            and (e.ends_at is null or e.ends_at>now())
        ))
      )
    )
  )
);
;
