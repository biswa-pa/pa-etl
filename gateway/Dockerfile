# PA ETL gateway: portal, and a branded front door for the official Cube, Prefect,
# Airbyte and ClickHouse images. Branding is injected here, so those images can
# be upgraded without rebuilding a themed copy.
FROM nginx:1.27-alpine
ENV PA_ETL_PORTAL_HOST=etl.localhost \
    PA_ETL_PREFECT_HOST=pipeline.localhost \
    PA_ETL_AIRBYTE_HOST=connecter.localhost \
    PA_ETL_PORTAL_URL=http://etl.localhost:8080 \
    PA_ETL_PREFECT_URL=http://localhost:8081 \
    PA_ETL_AIRBYTE_URL=http://localhost:8082 \
    PA_ETL_CUBE_URL=http://localhost:8083 \
    PA_ETL_CLICKHOUSE_URL=http://localhost:8084/play \
    AIRBYTE_UPSTREAM=host.docker.internal:8000 \
    AIRBYTE_HOST_HEADER=localhost \
    AIRBYTE_ORIGIN=http://localhost:8000 \
    CUBE_UPSTREAM=cube:4000 \
    CLICKHOUSE_UPSTREAM=clickhouse:8123
RUN apk add --no-cache openssl
COPY gateway/30-pa-etl-auth.sh /docker-entrypoint.d/30-pa-etl-auth.sh
COPY gateway/default.conf.template /etc/nginx/templates/default.conf.template
COPY gateway/portal/ /usr/share/nginx/html/
COPY brand/ /brand/
RUN chmod +x /docker-entrypoint.d/30-pa-etl-auth.sh
EXPOSE 80 8081 8082 8083 8084
