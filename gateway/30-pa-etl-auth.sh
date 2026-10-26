#!/bin/sh
# Optional password for the Prefect UI and API (Prefect has no login of its own).
# Set PA_ETL_PREFECT_USER and PA_ETL_PREFECT_PASSWORD to turn it on.
# Branding is always injected here, so Cube, Prefect, Airbyte and ClickHouse
# keep the PA ETL look when their own images are upgraded.
set -eu
CONF=/etc/nginx/pa-etl-prefect-auth.conf
if [ -n "${PA_ETL_PREFECT_USER:-}" ] && [ -n "${PA_ETL_PREFECT_PASSWORD:-}" ]; then
  HASH=$(openssl passwd -apr1 "$PA_ETL_PREFECT_PASSWORD")
  printf '%s:%s\n' "$PA_ETL_PREFECT_USER" "$HASH" > /etc/nginx/pa-etl.htpasswd
  printf 'auth_basic "PA ETL";\nauth_basic_user_file /etc/nginx/pa-etl.htpasswd;\n' > "$CONF"
  echo "pa-etl: Prefect UI password is on"
else
  printf 'auth_basic off;\n' > "$CONF"
  echo "pa-etl: Prefect UI has no password (set PA_ETL_PREFECT_USER and PA_ETL_PREFECT_PASSWORD)"
fi

# $1 app name (selects CSS), $2 output file
write_brand() {
  css="/__pa/apps.css"
  case "$1" in
    prefect) css="/__pa/prefect.css" ;;
    airbyte) css="/__pa/airbyte.css" ;;
    cube) css="/__pa/cube.css" ;;
    clickhouse) css="/__pa/clickhouse.css" ;;
  esac
  portal=$(printf '%s' "${PA_ETL_PORTAL_URL:-http://etl.localhost:8080}" | sed 's/"/%22/g')
  cat > "$2" <<NGINX
proxy_set_header Accept-Encoding "";
sub_filter_once off;
sub_filter_types text/html;
sub_filter '</head>' '<link rel="stylesheet" href="${css}?v=3"><script defer src="/__pa/brand.js?v=3&app=${1}&portal=${portal}"></script></head>';
NGINX
}

write_brand prefect /etc/nginx/pa-etl-brand-prefect.conf
write_brand airbyte /etc/nginx/pa-etl-brand-airbyte.conf
write_brand cube /etc/nginx/pa-etl-brand-cube.conf
write_brand clickhouse /etc/nginx/pa-etl-brand-clickhouse.conf
echo "pa-etl: branding Cube, Prefect, Airbyte and ClickHouse at the gateway"
