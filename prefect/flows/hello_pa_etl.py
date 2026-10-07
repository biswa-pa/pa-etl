from prefect import flow, get_run_logger


@flow(name="hello-pa-etl", log_prints=True)
def hello_pa_etl(name: str = "PA ETL"):
    """Smoke test: proves the worker can pick up and run a flow."""
    get_run_logger().info("Hello from %s", name)
    return f"Hello, {name}!"


if __name__ == "__main__":
    hello_pa_etl()
