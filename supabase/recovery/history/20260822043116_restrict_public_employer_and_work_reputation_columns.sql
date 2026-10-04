-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822043116
revoke select on table public.employers from anon;
grant select (id, company_name, industry, verified, website, description, logo_url, headquarters, sector_category, verification_status, company_size, founded_year, city, country, careers_url, linkedin_url) on table public.employers to anon;
revoke select on table public.work_reputation from anon;
grant select (user_id, rating_average, review_count, completed_contracts, currency, updated_at) on table public.work_reputation to anon;

;
