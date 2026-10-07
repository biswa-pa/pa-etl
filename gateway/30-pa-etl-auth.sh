#!/bin/sh
# Optional password for the Prefect UI and API (Prefect has no login of its own).
# Set PA_ETL_PREFECT_USER and PA_ETL_PREFECT_PASSWORD to turn it on.
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

# Optional: brand a stock Airbyte at the gateway (not needed with the pa-etl/airbyte-server image).
BRAND=/etc/nginx/pa-etl-brand-airbyte.conf
if [ "${AIRBYTE_BRAND_AT_GATEWAY:-false}" = "true" ]; then
  cat > "$BRAND" <<'NGINX'
proxy_set_header Accept-Encoding "";
sub_filter_once off;
sub_filter_types text/html;
sub_filter '</head>' '<link rel="stylesheet" href="/__pa/airbyte.css"><script defer src="/__pa/brand.js"></script></head>';
NGINX
  echo "pa-etl: branding Airbyte at the gateway"
else
  : > "$BRAND"
fi
