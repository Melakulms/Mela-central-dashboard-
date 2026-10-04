-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822105647
update storage.buckets set public=false where id='avatars';
;
