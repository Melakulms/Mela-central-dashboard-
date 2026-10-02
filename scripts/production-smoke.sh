#!/usr/bin/env bash
set -euo pipefail

APP_URL="${APP_URL:-https://melakulms.github.io/Mela-central-dashboard-/}"
SUPABASE_URL="${SUPABASE_URL:-https://duizgtmbptmlbyipreqg.supabase.co}"
SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
ADMIN_API_URL="${ADMIN_API_URL:-$SUPABASE_URL/functions/v1/mela-admin-api}"

if [[ -z "$SUPABASE_PUBLISHABLE_KEY" ]]; then
  echo "SUPABASE_PUBLISHABLE_KEY is required" >&2
  exit 1
fi

curl_common=(--fail --silent --show-error --location --retry 8 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 30)

echo "Checking deployed admin app: $APP_URL"
curl "${curl_common[@]}" --head "$APP_URL" >/dev/null

echo "Checking Supabase Auth health"
curl "${curl_common[@]}" "$SUPABASE_URL/auth/v1/health" >/dev/null

echo "Checking Supabase Data API availability"
curl "${curl_common[@]}" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" "$SUPABASE_URL/rest/v1/" >/dev/null

echo "Checking admin Edge Function gateway"
status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --retry 8 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 30 "$ADMIN_API_URL")"
case "$status" in
  401|403) ;;
  *) echo "Expected unauthenticated admin API to reject with 401/403; got $status" >&2; exit 1 ;;
esac

echo "Admin production smoke checks passed"
