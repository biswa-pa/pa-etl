"""Run Airbyte syncs from a Prefect flow.

Settings come from the environment of the worker:

  AIRBYTE_URL            default http://host.docker.internal:8000 (abctl on the same machine)
  AIRBYTE_CLIENT_ID      from `scripts/airbyte.sh credentials`
  AIRBYTE_CLIENT_SECRET  from `scripts/airbyte.sh credentials`

The Airbyte public API (v1) uses an application token: the client id and secret
are exchanged for a short-lived bearer token.
"""
import os
import time

import httpx
from prefect import get_run_logger, task

DEFAULT_URL = "http://host.docker.internal:8000"
DONE = {"succeeded"}
FAILED = {"failed", "cancelled"}


class AirbyteError(RuntimeError):
    pass


def _settings():
    url = os.environ.get("AIRBYTE_URL", DEFAULT_URL).rstrip("/")
    cid = os.environ.get("AIRBYTE_CLIENT_ID", "")
    secret = os.environ.get("AIRBYTE_CLIENT_SECRET", "")
    if not cid or not secret:
        raise AirbyteError("Set AIRBYTE_CLIENT_ID and AIRBYTE_CLIENT_SECRET (see scripts/airbyte.sh credentials).")
    return url, cid, secret


def _token(client: httpx.Client, url: str, cid: str, secret: str) -> str:
    resp = client.post(
        f"{url}/api/public/v1/applications/token",
        json={"client_id": cid, "client_secret": secret, "grant-type": "client_credentials"},
    )
    if resp.status_code != 200:
        raise AirbyteError(f"Could not get an Airbyte token ({resp.status_code}): {resp.text[:200]}")
    return resp.json()["access_token"]


def run_sync(connection_id: str, timeout_minutes: int = 120, poll_seconds: int = 10) -> dict:
    """Start a sync for one connection and wait for it. Returns the final job."""
    url, cid, secret = _settings()
    with httpx.Client(timeout=30) as client:
        headers = {"Authorization": f"Bearer {_token(client, url, cid, secret)}"}
        started = client.post(
            f"{url}/api/public/v1/jobs",
            headers=headers,
            json={"connectionId": connection_id, "jobType": "sync"},
        )
        if started.status_code not in (200, 201):
            raise AirbyteError(f"Could not start the sync ({started.status_code}): {started.text[:200]}")
        job_id = started.json()["jobId"]
        deadline = time.time() + timeout_minutes * 60
        while time.time() < deadline:
            job = client.get(f"{url}/api/public/v1/jobs/{job_id}", headers=headers).json()
            status = str(job.get("status", "")).lower()
            if status in DONE:
                return job
            if status in FAILED:
                raise AirbyteError(f"Airbyte job {job_id} ended as {status}.")
            time.sleep(poll_seconds)
    raise AirbyteError(f"Airbyte job {job_id} did not finish within {timeout_minutes} minutes.")


@task(name="airbyte-sync", retries=1, retry_delay_seconds=60)
def sync_connection(connection_id: str, timeout_minutes: int = 120) -> dict:
    """Prefect task wrapper around run_sync."""
    log = get_run_logger()
    log.info("Starting Airbyte sync for connection %s", connection_id)
    job = run_sync(connection_id, timeout_minutes)
    log.info("Airbyte job %s finished: %s rows synced", job.get("jobId"), job.get("rowsSynced"))
    return job
