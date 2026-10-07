# PA ETL gateway: portal page, host-based routing and branding for Prefect and Airbyte.
FROM nginx:1.27-alpine
ENV PA_ETL_PORTAL_HOST=etl.localhost \
    PA_ETL_PREFECT_HOST=prefect.localhost \
    PA_ETL_AIRBYTE_HOST=airbyte.localhost \
    PA_ETL_PORTAL_URL=http://etl.localhost:8080 \
    PA_ETL_PREFECT_URL=http://prefect.localhost:8080 \
    PA_ETL_AIRBYTE_URL=http://airbyte.localhost:8080 \
    AIRBYTE_UPSTREAM=host.docker.internal:8000 \
    AIRBYTE_HOST_HEADER=localhost
RUN apk add --no-cache openssl
COPY gateway/30-pa-etl-auth.sh /docker-entrypoint.d/30-pa-etl-auth.sh
COPY gateway/default.conf.template /etc/nginx/templates/default.conf.template
COPY gateway/portal/ /usr/share/nginx/html/
COPY brand/ /brand/
EXPOSE 80
