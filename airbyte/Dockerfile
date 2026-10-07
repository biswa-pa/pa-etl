# PA ETL Airbyte server: the official airbyte/server with the PA ETL look baked into its web UI.
# A drop-in replacement for airbyte/server (same tag, same settings).
ARG AIRBYTE_TAG=2.3.0

FROM airbyte/server:${AIRBYTE_TAG} AS base

FROM alpine:3.20 AS patch
ARG AIRBYTE_TAG
RUN apk add --no-cache zip unzip
COPY --from=base /app/airbyte-app/lib/io.airbyte-airbyte-server-${AIRBYTE_TAG}.jar /work/server.jar
COPY brand/ /brand/
COPY airbyte/patch-webapp.sh /patch-webapp.sh
RUN sh /patch-webapp.sh /work/server.jar /brand

FROM airbyte/server:${AIRBYTE_TAG}
ARG AIRBYTE_TAG
COPY --from=patch /work/server.jar /app/airbyte-app/lib/io.airbyte-airbyte-server-${AIRBYTE_TAG}.jar
