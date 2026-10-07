from prefect import flow

from pa_etl.airbyte import sync_connection


@flow(name="airbyte-sync", log_prints=True)
def airbyte_sync(connection_id: str, timeout_minutes: int = 120):
    """Run one Airbyte connection and wait for it to finish.

    Create a schedule for it in the Prefect UI (Deployments > airbyte-sync) and put the
    connection id from the Airbyte URL into the parameters.
    """
    job = sync_connection(connection_id, timeout_minutes)
    print(f"Sync finished, rows synced: {job.get('rowsSynced')}")
    return job
