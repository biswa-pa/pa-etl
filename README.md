# PA ETL

Self-hosted **Prefect** (pipelines) and **Airbyte** (data sync) behind one branded front door.

- **Data sync (Airbyte):** connect databases, apps and files and copy their data into your warehouse.
- **Pipelines (Prefect):** schedule flows, watch every run, retry failures, get alerts.
- **Portal:** a single page that links to both and shows whether each is running.

The look follows the other Predicta tools: orange `#FD9904` on purple-black `#1A0A22`.

```
 browser ──► gateway (nginx) ──┬─ etl.localhost      portal
                               ├─ pipeline.localhost  ──► Prefect server ◄── worker (runs your flows)
                               │                          └─ Postgres
                               └─ connecter.localhost  ──► Airbyte (abctl, own small Kubernetes)
```

Prefect, the worker, Postgres and the gateway run from Docker Compose. **Airbyte cannot**: it no longer ships a Compose file, and its supported local install is `abctl`, which runs Airbyte in a small Kubernetes cluster inside Docker. `scripts/airbyte.sh` wraps that, and the gateway puts it behind the same address and branding.

## Quick start

You need Docker (about 8 GB of memory free for Airbyte).

```bash
cp .env.example .env          # optional, everything has a default
docker compose up -d          # Prefect, the worker, the gateway and the portal
scripts/airbyte.sh install    # Airbyte: several GB, 10 to 20 minutes the first time
scripts/airbyte.sh env        # lets Prefect flows start Airbyte syncs
docker compose up -d prefect-worker
```

Open **http://etl.localhost:8080**. `*.localhost` names resolve to your own machine in current browsers, so nothing needs to be added to `/etc/hosts`.

| Address | What it is |
|---|---|
| http://etl.localhost:8080 | portal |
| http://pipeline.localhost:8080 | Prefect UI (Pipelines) |
| http://connecter.localhost:8080 | Airbyte UI (Data sync) |

The first Airbyte visit asks you to create the owner login. `scripts/airbyte.sh credentials` prints the API client id and secret.

## Running your own flows

The worker runs flows from `/opt/pa-etl/flows`. Two examples are registered on first start:

- `hello-pa-etl`: a smoke test. Run it from the Prefect UI (Deployments > hello-pa-etl > Run).
- `airbyte-sync`: starts one Airbyte connection and waits for it. Put the connection id (the long id in the Airbyte connection URL) in its parameters, and add a schedule in the UI.

To use your own flows, mount a folder over the example one and register deployments with Prefect as usual:

```yaml
# docker-compose.override.yml
services:
  prefect-worker:
    volumes:
      - ./my-flows:/opt/pa-etl/flows
```

In a flow, `from pa_etl.airbyte import sync_connection` gives you a Prefect task that starts a sync and waits for it (retries once). The worker reads `AIRBYTE_URL`, `AIRBYTE_CLIENT_ID` and `AIRBYTE_CLIENT_SECRET` from `.env`.

## Settings

Everything is optional and goes in `.env` (see `.env.example`).

| Setting | Default | Meaning |
|---|---|---|
| `PA_ETL_PORT` | `8080` | port the gateway listens on |
| `PA_ETL_*_HOST`, `PA_ETL_*_URL` | `*.localhost` | the three names and addresses people use |
| `PA_ETL_PREFECT_USER`, `PA_ETL_PREFECT_PASSWORD` | empty | put a password on the Prefect UI and API |
| `POSTGRES_PASSWORD` | `pa-etl-change-me` | Prefect database password (inside the Compose network only) |
| `AIRBYTE_URL` | `http://host.docker.internal:8000` | where the worker and gateway find Airbyte |
| `PA_IMAGE_PREFIX`, `PA_VERSION` | `pa-etl`, `1.0.0` | image names |

**Prefect has no login of its own.** Before exposing PA ETL beyond your machine, set `PA_ETL_PREFECT_USER` and `PA_ETL_PREFECT_PASSWORD`, and change `POSTGRES_PASSWORD`. Airbyte has its own login.

### Real hostnames and TLS

Point three DNS names at the gateway, set the `PA_ETL_*_HOST` and `PA_ETL_*_URL` values to them, and put your TLS proxy or load balancer in front of the gateway port. Example:

```
PA_ETL_PORTAL_HOST=etl.example.com      PA_ETL_PORTAL_URL=https://etl.example.com
PA_ETL_PREFECT_HOST=prefect.example.com PA_ETL_PREFECT_URL=https://prefect.example.com
PA_ETL_AIRBYTE_HOST=airbyte.example.com PA_ETL_AIRBYTE_URL=https://airbyte.example.com
```

If Airbyte runs on another machine, set `AIRBYTE_UPSTREAM` (host:port) and, if its ingress expects a host name, `AIRBYTE_HOST_HEADER`. For Airbyte on a Kubernetes cluster, use the Helm chart there and point `AIRBYTE_UPSTREAM` at its ingress.

## Images

| Image | What it holds |
|---|---|
| `pa-etl/prefect` | official Prefect with the `pa_etl` helpers and example flows. Used for the server and the worker |
| `pa-etl/gateway` | portal page, host routing, and the PA ETL branding for Prefect and Airbyte |

Postgres is the official `postgres:16-alpine`. Airbyte is installed by `scripts/airbyte.sh` and is not part of these images.

```bash
scripts/build-images.sh                          # build and tag 1.0.0 and latest
PA_IMAGE_PREFIX=ghcr.io/your-org/pa-etl scripts/build-images.sh --push
scripts/build-images.sh --save pa-etl.tar        # one file for offline use, then: docker load -i pa-etl.tar
```

`.github/workflows/publish.yml` builds and publishes both images (amd64 and arm64) to GitHub Container Registry on every push to `main` and on `v*` tags. After the first run, set each package to Public on GitHub so others can pull without logging in.

## How the branding works

- **Prefect:** both of its UIs are themed with CSS variables, so `brand/prefect.css` swaps the colours and the logo, and the gateway adds that file, the tab icon and the title to every page. The newer V2 UI (`/v2/...`) gets a dark purple sidebar with an orange active edge, soft cards, a matching dark mode, and no Prefect Cloud upsell. `brand/brand.js` swaps its logo and removes the community link.
- **Airbyte:** same idea with `brand/airbyte.css`, added by the gateway. This styles an app we do not build, so check it after an Airbyte upgrade.
- **Airbyte layout:** `brand/airbyte.css` gives Airbyte the same look as Prefect V2: a dark purple sidebar with an orange active edge, a soft purple-grey page, rounded connector cards that lift on hover, a larger search box, and orange tab underlines. Light and dark mode each have their own colour scale, because Airbyte inverts its scale in dark mode.
- **Airbyte logo and animation:** `brand/brand.js` replaces the sign-in logo, the sidebar logo, the big mark and glow in the "Connections link Sources to Destinations" illustration, and the page loader with the PA ETL mark. `brand/mark-animated.svg` is the animated version (a data dot flowing through the transform step). The original elements are hidden, not removed, because Airbyte's React code owns them and would error if they disappeared.
- **Names inside the pages:** `brand/brand.js` runs in both UIs. It changes the tab title, the tab icon and every visible "Prefect" or "Airbyte" to "PA ETL", and hides Prefect's unbranded "Switch to V2 UI" button. Code blocks, editors and form fields are left alone, so snippets such as `from prefect import flow` stay correct. Names you typed yourself (a flow or connection called "Airbyte test") also read as "PA ETL" on screen, but are unchanged in the data.
- **Portal and gateway:** `gateway/`. Brand files (logo, mark, icons) are in `brand/`.

## Commands

```bash
docker compose ps                       # what is running
docker compose logs -f prefect-worker   # watch flow runs
scripts/airbyte.sh status               # Airbyte
scripts/airbyte.sh uninstall            # remove Airbyte (add --persisted to delete its data)
docker compose down                     # stop PA ETL (add -v to delete the Prefect database)
```

## Troubleshooting

- **Airbyte install fails with `UnknownHostException: connectors.airbyte.com`.** On Docker Desktop the cluster's DNS can time out on UDP. `scripts/airbyte.sh install` already fixes this by sending CoreDNS's upstream lookups over TCP. If you installed Airbyte another way, run the install through the script instead.
- **Airbyte shows a blank page behind the gateway.** Airbyte's ingress answers 403 to any request whose `Origin` is not its own address. The gateway rewrites `Origin` to `AIRBYTE_ORIGIN` (default `http://localhost:8000`). If Airbyte runs elsewhere, set `AIRBYTE_ORIGIN` to the address it expects.
- **Airbyte first visit.** It asks for an owner email and organisation name once. After that, sign in with the password from `scripts/airbyte.sh credentials`.
- **`*.localhost` does not open.** Current Chrome, Firefox and Safari resolve it. If yours does not, add `127.0.0.1 etl.localhost pipeline.localhost connecter.localhost` to `/etc/hosts`.

## Notes

- Airbyte needs real memory. `scripts/airbyte.sh` installs in low-resource mode by default (`AIRBYTE_LOW_RESOURCE=0` to turn that off). With Docker Desktop, give it at least 8 GB.
- `scripts/airbyte.sh` downloads `abctl` from Airbyte's GitHub releases, checks its SHA-256 against Airbyte's published checksum, and keeps it in `~/.pa-etl/bin`. Nothing is installed system-wide.
- Prefect and Airbyte are open-source projects under their own licences. PA ETL only wraps and re-skins them.
