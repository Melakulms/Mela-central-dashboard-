-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815054123
create index if not exists mela_learning_material_translations_reviewed_by_idx on public.mela_learning_material_translations(reviewed_by);
create index if not exists mela_learning_materials_product_key_idx on public.mela_learning_materials(product_key);
create index if not exists mela_learning_source_requirements_reviewed_by_idx on public.mela_learning_source_requirements(reviewed_by);

-- Products: separate anon/authenticated reads and admin mutations to avoid overlapping SELECT policies.
drop policy if exists mela_learning_products_public_read on public.mela_learning_products;
drop policy if exists mela_learning_products_admin_write on public.mela_learning_products;
create policy mela_learning_products_anon_read on public.mela_learning_products for select to anon using (active);
create policy mela_learning_products_authenticated_read on public.mela_learning_products for select to authenticated using (active or private.is_admin_user());
create policy mela_learning_products_admin_insert on public.mela_learning_products for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_products_admin_update on public.mela_learning_products for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_products_admin_delete on public.mela_learning_products for delete to authenticated using (private.is_admin_user());

-- Programs.
drop policy if exists mela_learning_programs_public_read on public.mela_learning_programs;
drop policy if exists mela_learning_programs_admin_write on public.mela_learning_programs;
create policy mela_learning_programs_anon_read on public.mela_learning_programs for select to anon using (active);
create policy mela_learning_programs_authenticated_read on public.mela_learning_programs for select to authenticated using (active or private.is_admin_user());
create policy mela_learning_programs_admin_insert on public.mela_learning_programs for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_programs_admin_update on public.mela_learning_programs for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_programs_admin_delete on public.mela_learning_programs for delete to authenticated using (private.is_admin_user());

-- Units.
drop policy if exists mela_learning_units_public_read on public.mela_learning_units;
drop policy if exists mela_learning_units_admin_write on public.mela_learning_units;
create policy mela_learning_units_anon_read on public.mela_learning_units for select to anon using (status='published');
create policy mela_learning_units_authenticated_read on public.mela_learning_units for select to authenticated using (status='published' or private.is_admin_user());
create policy mela_learning_units_admin_insert on public.mela_learning_units for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_units_admin_update on public.mela_learning_units for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_units_admin_delete on public.mela_learning_units for delete to authenticated using (private.is_admin_user());

-- Material metadata.
drop policy if exists mela_learning_materials_public_read on public.mela_learning_materials;
drop policy if exists mela_learning_materials_admin_write on public.mela_learning_materials;
create policy mela_learning_materials_anon_read on public.mela_learning_materials for select to anon using (status='published');
create policy mela_learning_materials_authenticated_read on public.mela_learning_materials for select to authenticated using (status='published' or private.is_admin_user());
create policy mela_learning_materials_admin_insert on public.mela_learning_materials for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_materials_admin_update on public.mela_learning_materials for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_materials_admin_delete on public.mela_learning_materials for delete to authenticated using (private.is_admin_user());

-- Material content: extend the single authenticated read policy to admins, then split admin mutations.
drop policy if exists mela_learning_material_content_authenticated on public.mela_learning_material_content;
drop policy if exists mela_learning_material_content_admin_write on public.mela_learning_material_content;
create policy mela_learning_material_content_authenticated on public.mela_learning_material_content for select to authenticated using (
  private.is_admin_user() or exists(
    select 1 from public.mela_learning_materials m
    where m.id=material_id and m.status='published' and (
      m.access_tier='free'
      or (m.access_tier='subscription' and exists(
        select 1 from public.mela_user_learning_entitlements e
        join public.mela_learning_products p on p.product_key=e.product_key
        where e.user_id=(select auth.uid()) and e.status='active' and p.product_type in ('subscription','institution')
          and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      ))
      or (m.access_tier='one_time' and exists(
        select 1 from public.mela_user_learning_entitlements e
        where e.user_id=(select auth.uid()) and e.status='active' and e.product_key=m.product_key
          and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      ))
    )
  )
);
create policy mela_learning_material_content_admin_insert on public.mela_learning_material_content for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_material_content_admin_update on public.mela_learning_material_content for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_material_content_admin_delete on public.mela_learning_material_content for delete to authenticated using (private.is_admin_user());

-- Translations.
drop policy if exists mela_learning_material_translations_admin_write on public.mela_learning_material_translations;
create policy mela_learning_material_translations_admin_insert on public.mela_learning_material_translations for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_material_translations_admin_update on public.mela_learning_material_translations for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_material_translations_admin_delete on public.mela_learning_material_translations for delete to authenticated using (private.is_admin_user());

-- Entitlements.
drop policy if exists mela_user_learning_entitlements_admin_write on public.mela_user_learning_entitlements;
create policy mela_user_learning_entitlements_admin_insert on public.mela_user_learning_entitlements for insert to authenticated with check (private.is_admin_user());
create policy mela_user_learning_entitlements_admin_update on public.mela_user_learning_entitlements for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_user_learning_entitlements_admin_delete on public.mela_user_learning_entitlements for delete to authenticated using (private.is_admin_user());

-- Source review queue.
drop policy if exists mela_learning_source_requirements_admin_write on public.mela_learning_source_requirements;
create policy mela_learning_source_requirements_admin_insert on public.mela_learning_source_requirements for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_source_requirements_admin_update on public.mela_learning_source_requirements for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_source_requirements_admin_delete on public.mela_learning_source_requirements for delete to authenticated using (private.is_admin_user());
;
