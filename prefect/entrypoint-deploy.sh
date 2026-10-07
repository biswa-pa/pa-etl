#!/bin/sh
# One-shot: make sure the work pool exists and register the example deployments.
set -eu
POOL="${PA_ETL_WORK_POOL:-pa-etl}"
prefect work-pool inspect "$POOL" >/dev/null 2>&1 || prefect work-pool create "$POOL" --type process
python - <<PY
from prefect import flow

POOL = "${POOL}"
SOURCE = "/opt/pa-etl/flows"
for entry, name in (
    ("hello_pa_etl.py:hello_pa_etl", "hello-pa-etl"),
    ("airbyte_sync.py:airbyte_sync", "airbyte-sync"),
):
    flow.from_source(source=SOURCE, entrypoint=entry).deploy(name=name, work_pool_name=POOL, build=False, push=False)
PY
echo "pa-etl: work pool '$POOL' ready and example deployments registered"
