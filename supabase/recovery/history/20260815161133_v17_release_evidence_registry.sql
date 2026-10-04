-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815161133
create table if not exists private.mela_release_evidence (
  id bigint generated always as identity primary key,
  release_version text not null,
  evidence_key text not null,
  evidence_kind text not null check (evidence_kind in ('benchmark','backup_manifest','security','qa','operations')),
  status text not null check (status in ('pass','informational','pending','blocked')),
  measured_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  note text,
  unique(release_version,evidence_key)
);
revoke all on private.mela_release_evidence from public, anon, authenticated;
grant select, insert, update on private.mela_release_evidence to service_role;
grant usage, select on sequence private.mela_release_evidence_id_seq to service_role;
;
