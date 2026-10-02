#!/usr/bin/env bash
set -euo pipefail

APP_URL="${APP_URL:-https://melakulms.github.io/Mela-central-dashboard-/}"
SUPABASE_URL="${SUPABASE_URL:-https://duizgtmbptmlbyipreqg.supabase.co}"
SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
ADMIN_API_URL="${ADMIN_API_URL:-$SUPABASE_URL/functions/v1/mela-admin-api}"
TARGET="${1:-all}"

if [[ -z "$SUPABASE_PUBLISHABLE_KEY" ]]; then
  echo "SUPABASE_PUBLISHABLE_KEY is required" >&2
  exit 1
fi

curl_common=(--fail --silent --show-error --location --retry 8 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 30)

check_app() {
  echo "Checking deployed admin app: $APP_URL"
  curl "${curl_common[@]}" --output /dev/null "$APP_URL"
}

check_auth() {
  echo "Checking Supabase Auth health"
  curl "${curl_common[@]}" --output /dev/null -H "apikey: $SUPABASE_PUBLISHABLE_KEY" "$SUPABASE_URL/auth/v1/health"
}

check_data() {
  echo "Checking application Data API access through platform_languages"
  curl "${curl_common[@]}" --output /dev/null \
    -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    -H "Accept: application/json" \
    "$SUPABASE_URL/rest/v1/platform_languages?select=language_code&enabled=eq.true&limit=1"
}

check_admin_api() {
  echo "Checking admin Edge Function gateway"
  status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --retry 8 --retry-delay 5 --retry-all-errors --connect-timeout 10 --max-time 30 "$ADMIN_API_URL")"
  case "$status" in
    401|403) ;;
    *) echo "Expected unauthenticated admin API to reject with 401/403; got $status" >&2; exit 1 ;;
  esac
}

case "$TARGET" in
  app) check_app ;;
  auth) check_auth ;;
  data) check_data ;;
  admin-api) check_admin_api ;;
  all) check_app; check_auth; check_data; check_admin_api ;;
  *) echo "Unknown smoke target: $TARGET" >&2; exit 2 ;;
esac
