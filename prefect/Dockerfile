# PA ETL pipelines image: official Prefect plus the pa_etl helpers and example flows.
# Used for both the Prefect server and the worker.
ARG PREFECT_TAG=3.8.8-python3.12
FROM prefecthq/prefect:${PREFECT_TAG}

ENV PYTHONPATH=/opt/pa-etl \
    PREFECT_SERVER_ANALYTICS_ENABLED=false \
    PREFECT_SERVER_API_HOST=0.0.0.0

COPY prefect/pa_etl /opt/pa-etl/pa_etl
COPY prefect/flows /opt/pa-etl/flows
COPY prefect/entrypoint-deploy.sh /usr/local/bin/pa-etl-deploy
RUN chmod +x /usr/local/bin/pa-etl-deploy
WORKDIR /opt/pa-etl
