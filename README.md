# PA ETL

Self-hosted **Prefect** (pipelines) and **Airbyte** (data sync) with the PA ETL look, behind one front door.

- **Data sync (Airbyte):** connect databases, apps and files and copy their data into your warehouse.
- **Pipelines (Prefect):** schedule flows, watch every run, retry failures, get alerts.
- **Portal:** a single page that links to both and shows whether each is running.

The look follows the other Predicta tools: orange `#FD9904` on purple-black `#1A0A22`.

```
 browser ──► gateway (nginx) ──┬─ etl.example.com       portal
                               ├─ pipeline.example.com  ──► Prefect server ◄── worker (runs your flows)
                               │                            └─ Postgres
                               └─ connecter.example.com ──► Airbyte (abctl, its own small Kubernetes)
```

Prefect, the worker, Postgres and the gateway run from Docker Compose. **Airbyte cannot**: it no longer ships a Compose file, and its supported install is `abctl`, which runs Airbyte in a small Kubernetes cluster inside Docker. `scripts/airbyte.sh` wraps that.

## The images

The branding is built into the images, so they work on their own and can be used in place of the official ones.

| Image | Replaces | What is different |
|---|---|---|
| `ghcr.io/biswa-pa/pa-etl/prefect` | `prefecthq/prefect` | PA ETL look in both Prefect UIs, plus the `pa_etl` helpers and two example flows. Same commands and settings as the official image |
| `ghcr.io/biswa-pa/pa-etl/airbyte-server` | `airbyte/server` | PA ETL look in Airbyte's web UI (sign-in, sidebar, animation, loader, colours). Same version tag as Airbyte, same settings |
| `ghcr.io/biswa-pa/pa-etl/gateway` | (new) | Portal page and host-name routing in front of the two apps. Optional |

All three are built for **linux/amd64 and linux/arm64** (Ubuntu servers and Apple-silicon Macs). The workflow in `.github/workflows/publish.yml` publishes them on every push to `main`. After the first run, set each package to **Public** on GitHub (Packages) so others can pull without logging in.

### Use them instead of the official images

**Prefect**, in Docker Compose. Change only the image line; the command, environment and volumes stay as they are:

```yaml
services:
  prefect-server:
    # image: prefecthq/prefect:3.8.8-python3.12
    image: ghcr.io/biswa-pa/pa-etl/prefect:latest
    command: prefect server start --host 0.0.0.0
```

For the Prefect Helm chart, set `server.image.repository: ghcr.io/biswa-pa/pa-etl/prefect` and `server.image.prefectTag: latest` in your values (check the key names against your chart version).

**Airbyte**, with the Helm chart (or `abctl local install --values values.yaml`):

```yaml
server:
  image:
    repository: ghcr.io/biswa-pa/pa-etl/airbyte-server
    # tag: left out, so it follows the chart's app version (for example 2.3.0)
```

The image tag is the Airbyte version it is built on (`2.3.0`), so it always matches the chart. `scripts/airbyte.sh install` does this for you.

Pin a tag (`:sha-<commit>`, or a release tag such as `:1.0.0` once you create `v1.0.0`) for production instead of `:latest`. The images only add branding to the official ones; they do not change Prefect's or Airbyte's behaviour.

## Quick start

You need Docker with the Compose plugin (about 8 GB of free memory for Airbyte).

```bash
cp .env.example .env          # optional, everything has a default
docker compose up -d          # pulls the images: Prefect, the worker, the gateway and the portal
scripts/airbyte.sh install    # Airbyte: several GB, 10 to 20 minutes the first time
scripts/airbyte.sh env        # lets Prefect flows start Airbyte syncs
docker compose up -d prefect-worker
```

To build the images from this repo instead of pulling them, use `docker compose up -d --build`.

Open **http://etl.localhost:8080**. On your own machine, `*.localhost` names resolve by themselves, so nothing needs to be added to `/etc/hosts`.

| Address | What it is |
|---|---|
| http://etl.localhost:8080 | portal |
| http://pipeline.localhost:8080 | Prefect UI (Pipelines) |
| http://connecter.localhost:8080 | Airbyte UI (Data sync) |

The first Airbyte visit asks you to create the owner login. `scripts/airbyte.sh credentials` prints the password and the API client id and secret.

## Running on an Ubuntu server

These steps are for Ubuntu 22.04 or 24.04. They follow the Docker, Airbyte and Prefect documentation; the stack has been run and tested on a Mac, not on Ubuntu, so read each step and try it on a test server first.

**1. Requirements.** 4 CPU cores and 8 GB RAM at least (Airbyte is the heavy part), 40 GB of disk, and Docker Engine with the Compose plugin ([install guide](https://docs.docker.com/engine/install/ubuntu/)):

```bash
sudo systemctl enable --now docker          # start Docker at boot
sudo usermod -aG docker $USER               # then log out and in again
```

**2. Kernel limits.** The cluster inside Airbyte (kind) needs higher inotify limits than Ubuntu's defaults, or the install fails with "too many open files":

```bash
printf 'fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=524288\n' | sudo tee /etc/sysctl.d/99-pa-etl.conf
sudo sysctl --system
```

`scripts/airbyte.sh install` warns if the limits are low.

**3. DNS.** Create three records pointing at the server, for example `etl.example.com`, `pipeline.example.com` and `connecter.example.com`. Put them in `.env`:

```
PA_ETL_PORTAL_HOST=etl.example.com        PA_ETL_PORTAL_URL=https://etl.example.com
PA_ETL_PREFECT_HOST=pipeline.example.com  PA_ETL_PREFECT_URL=https://pipeline.example.com
PA_ETL_AIRBYTE_HOST=connecter.example.com PA_ETL_AIRBYTE_URL=https://connecter.example.com
PA_ETL_BIND=127.0.0.1
PA_ETL_PREFECT_USER=admin
PA_ETL_PREFECT_PASSWORD=choose-a-long-password
POSTGRES_PASSWORD=choose-another-one
```

`PA_ETL_BIND=127.0.0.1` keeps the gateway reachable only from the server itself, so only your TLS proxy can talk to it. **Prefect has no login of its own**, so always set the user and password before exposing it. Airbyte has its own login.

**4. TLS.** Put a reverse proxy in front of the gateway. With [Caddy](https://caddyserver.com/docs/install#debian-ubuntu-raspbian), which gets certificates by itself:

```
# /etc/caddy/Caddyfile
etl.example.com, pipeline.example.com, connecter.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

The gateway chooses the app from the host name, so one proxy rule covers all three.

**5. Start it.**

```bash
docker compose up -d
scripts/airbyte.sh install
scripts/airbyte.sh env && docker compose up -d prefect-worker
```

Airbyte is set to restart with Docker, and the Compose services restart on their own, so everything comes back after a reboot.

**6. Keep Airbyte's port private.** Airbyte listens on port 8000 on all interfaces, and Docker publishes ports around `ufw`. Only the gateway needs it, so block outside access to it (replace `eth0` with your public network interface), and make the rule permanent with `iptables-persistent`:

```bash
sudo iptables -I DOCKER-USER -i eth0 -p tcp -m conntrack --ctorigdstport 8000 --ctdir ORIGINAL -j DROP
```

Open only ports 80 and 443 in your firewall. If the gateway cannot reach Airbyte through `ufw`, allow the Docker network to reach the host: `sudo ufw allow from 172.16.0.0/12 to any port 8000`.

**7. Updates and backups.**

```bash
docker compose pull && docker compose up -d     # new PA ETL images
```

For Airbyte, set `AIRBYTE_TAG` in `.env.example` and the Helm chart version together, then re-run `scripts/airbyte.sh install`. Back up the Docker volume `pa-etl_postgres_data` (Prefect's database) and Airbyte's data folder `~/.airbyte/abctl/data`.

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
| `PA_ETL_PORT`, `PA_ETL_BIND` | `8080`, `0.0.0.0` | port and address the gateway listens on |
| `PA_ETL_*_HOST`, `PA_ETL_*_URL` | `*.localhost` | the three names and addresses people use |
| `PA_ETL_PREFECT_USER`, `PA_ETL_PREFECT_PASSWORD` | empty | put a password on the Prefect UI and API |
| `POSTGRES_PASSWORD` | `pa-etl-change-me` | Prefect database password (inside the Compose network only) |
| `AIRBYTE_URL`, `AIRBYTE_UPSTREAM` | `host.docker.internal:8000` | where the worker and gateway find Airbyte |
| `AIRBYTE_BRAND_AT_GATEWAY` | `false` | set to `true` only if you run stock Airbyte, to brand it at the gateway |
| `PA_IMAGE_PREFIX`, `PA_VERSION` | `ghcr.io/biswa-pa/pa-etl`, `latest` | which images to use |

If Airbyte runs on another machine, set `AIRBYTE_UPSTREAM` (host:port) and, if its ingress expects a host name, `AIRBYTE_HOST_HEADER`. For Airbyte on a Kubernetes cluster, use the Helm chart there with the values above and point `AIRBYTE_UPSTREAM` at its ingress.

## Build and publish

```bash
scripts/build-images.sh                          # build and tag all three images
PA_IMAGE_PREFIX=ghcr.io/your-org/pa-etl scripts/build-images.sh --push
scripts/build-images.sh --save pa-etl.tar        # one file for offline use, then: docker load -i pa-etl.tar
```

The Prefect and gateway images are versioned by `VERSION` (and `:latest`). The Airbyte image is versioned by the Airbyte release it is built on (`AIRBYTE_TAG`).

## How the branding works

- **Prefect:** `prefect/brand_ui.py` runs when the image is built. It copies the brand files into Prefect's own UI folders, patches both `index.html` files to load them, and swaps the icons. Both UIs are themed with CSS variables, so `brand/prefect.css` changes colours and the logo. The V2 UI (`/v2/...`) gets a dark purple sidebar with an orange active edge, soft cards, a matching dark mode, and no Prefect Cloud upsell.
- **Airbyte:** `airbyte/patch-webapp.sh` runs when the image is built. Airbyte serves its UI from inside its server jar, so the script adds the brand files to that jar (served from `/assets/pa/`, the only static folder Airbyte serves) and patches `index.html` and the icons. `brand/airbyte.css` gives it the same look as Prefect V2: dark purple sidebar with an orange active edge, a soft purple-grey page, rounded connector cards that lift on hover, a larger search box, orange tab underlines. Light and dark mode each have their own colour scale, because Airbyte inverts its scale in dark mode.
- **Airbyte logo and animation:** `brand/brand.js` replaces the sign-in logo, the sidebar logo, the big mark and glow in the "Connections link Sources to Destinations" illustration, and the page loader with the PA ETL mark. `brand/mark-animated.svg` is the animated version (a data dot flowing through the transform step). The original elements are hidden, not removed, because Airbyte's React code owns them and would error if they disappeared.
- **Names inside the pages:** `brand/brand.js` changes the tab title, the tab icon and every visible "Prefect" or "Airbyte" to "PA ETL". Code blocks, editors and form fields are left alone, so snippets such as `from prefect import flow` stay correct. Names you typed yourself (a flow or connection called "Airbyte test") also read as "PA ETL" on screen, but are unchanged in the data.
- **Portal and gateway:** `gateway/`. Brand files (logo, mark, icons) are in `brand/`.

The brand files find each other by the folder they were loaded from, so the same files work from `/__pa/` (portal, gateway), `/assets/pa/` (Airbyte) and the Prefect UI folders.

This restyles two apps we do not build, so check the UIs after upgrading Prefect or Airbyte.

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
- **Airbyte install fails with "too many open files" on Linux.** Raise the inotify limits (server step 2).
- **Airbyte first visit.** It asks for an owner email and organisation name once. After that, sign in with the password from `scripts/airbyte.sh credentials`.
- **`*.localhost` does not open.** Current Chrome, Firefox and Safari resolve it. If yours does not, add `127.0.0.1 etl.localhost pipeline.localhost connecter.localhost` to `/etc/hosts`.
- **Airbyte looks unbranded.** It is running the stock server image. Reinstall with `scripts/airbyte.sh install` (it uses the PA ETL image), or set `AIRBYTE_BRAND_AT_GATEWAY=true`.

## Notes

- Airbyte needs real memory. `scripts/airbyte.sh` installs in low-resource mode by default (`AIRBYTE_LOW_RESOURCE=0` to turn that off). With Docker Desktop, give it at least 8 GB.
- `scripts/airbyte.sh` downloads `abctl` from Airbyte's GitHub releases, checks its SHA-256 against Airbyte's published checksum, and keeps it in `~/.pa-etl/bin`. Nothing is installed system-wide.
- Prefect and Airbyte are open-source projects under their own licences. PA ETL only wraps and re-skins them.
