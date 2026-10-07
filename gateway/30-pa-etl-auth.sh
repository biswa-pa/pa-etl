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
