#!/usr/bin/env bash
# Install and manage Airbyte for PA ETL.
#
# Airbyte no longer ships a Docker Compose file. Its supported local install is
# abctl, which runs Airbyte in a small Kubernetes cluster inside Docker. This
# script downloads abctl (checksum verified), installs Airbyte on port 8000, and
# wraps the commands you need. The PA ETL gateway then serves it with PA ETL branding.
#
#   scripts/airbyte.sh install       download abctl if needed, install Airbyte (several GB, 10-20 min)
#   scripts/airbyte.sh status        is it running?
#   scripts/airbyte.sh credentials   UI login and the API client id/secret
#   scripts/airbyte.sh env           write AIRBYTE_CLIENT_ID/SECRET into .env for the Prefect worker
#   scripts/airbyte.sh uninstall     remove Airbyte (add --persisted to delete its data too)
#
# Settings: AIRBYTE_PORT (8000), AIRBYTE_LOW_RESOURCE (1 = less memory), ABCTL_VERSION (v0.30.4),
#           PA_ETL_HOME (~/.pa-etl, where abctl is kept),
#           AIRBYTE_BRANDED (1 = install with the PA ETL airbyte-server image, 0 = stock Airbyte),
#           AIRBYTE_SERVER_IMAGE (ghcr.io/biswa-pa/pa-etl/airbyte-server),
#           AIRBYTE_HOST (optional: the public host name Airbyte is reached by, for direct access)
set -euo pipefail
cd "$(dirname "$0")/.."

ABCTL_VERSION="${ABCTL_VERSION:-v0.30.4}"
PORT="${AIRBYTE_PORT:-8000}"
LOW="${AIRBYTE_LOW_RESOURCE:-1}"
HOME_DIR="${PA_ETL_HOME:-$HOME/.pa-etl}"
BIN="$HOME_DIR/bin/abctl-$ABCTL_VERSION"
export DO_NOT_TRACK=1

BRANDED="${AIRBYTE_BRANDED:-1}"
SERVER_IMAGE="${AIRBYTE_SERVER_IMAGE:-ghcr.io/biswa-pa/pa-etl/airbyte-server}"

# Helm values: use the PA ETL Airbyte server image, which has the PA ETL look built into its web UI.
# Its tag defaults to the chart's app version, and the image is published with that same tag.
write_values() {
  mkdir -p "$HOME_DIR"
  VALUES="$HOME_DIR/airbyte-values.yaml"
  cat > "$VALUES" <<YAML
server:
  image:
    repository: $SERVER_IMAGE
YAML
}

# kind (the cluster inside abctl) needs generous inotify limits. Ubuntu's defaults are low and the
# install then fails with "too many open files". Warn early with the fix.
check_linux() {
  [[ "$(uname -s)" == "Linux" ]] || return 0
  local inst watches
  inst="$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"
  watches="$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)"
  if (( inst < 512 || watches < 524288 )); then
    echo "Warning: inotify limits are low (instances=$inst, watches=$watches). If the install fails with 'too many open files', run:" >&2
    echo "  sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=524288" >&2
    echo "  (make it permanent: add those two lines to /etc/sysctl.d/99-pa-etl.conf)" >&2
  fi
  docker info >/dev/null 2>&1 || echo "Warning: your user cannot talk to Docker. Add it to the docker group (sudo usermod -aG docker \$USER, then log in again)." >&2
}

need_docker() { docker info >/dev/null 2>&1 || { echo "Docker is not running." >&2; exit 1; }; }

ensure_abctl() {
  [[ -x "$BIN" ]] && return
  local os arch name base sum want
  case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) echo "Unsupported OS: $(uname -s). Use WSL or Linux." >&2; exit 1 ;; esac
  case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; *) echo "Unsupported CPU: $(uname -m)" >&2; exit 1 ;; esac
  name="abctl-$ABCTL_VERSION-$os-$arch.tar.gz"
  base="https://github.com/airbytehq/abctl/releases/download/$ABCTL_VERSION"
  mkdir -p "$HOME_DIR/bin"
  local tmp; tmp="$(mktemp -d)"
  echo "Downloading $name from github.com/airbytehq/abctl ..."
  curl -fsSL -o "$tmp/$name" "$base/$name"
  curl -fsSL -o "$tmp/checksums.txt" "$base/abctl_${ABCTL_VERSION#v}_checksums.txt"
  want="$(grep " $name\$" "$tmp/checksums.txt" | awk '{print $1}')"
  sum="$( (shasum -a 256 "$tmp/$name" 2>/dev/null || sha256sum "$tmp/$name") | awk '{print $1}')"
  [[ -n "$want" && "$want" == "$sum" ]] || { echo "Checksum mismatch for $name, not installing." >&2; exit 1; }
  tar -xzf "$tmp/$name" -C "$tmp"
  install -m 0755 "$tmp/abctl-$ABCTL_VERSION-$os-$arch/abctl" "$BIN"
  rm -r "$tmp"
  echo "abctl $ABCTL_VERSION installed in $HOME_DIR/bin (checksum ok)."
}

# On Docker Desktop the cluster's DNS can time out on UDP to Docker's resolver, which
# makes Airbyte's bootloader fail with "UnknownHostException: connectors.airbyte.com".
# Sending CoreDNS's upstream lookups over TCP fixes it. Runs beside the install and
# patches CoreDNS as soon as the cluster exists. Uses kubectl inside the cluster
# node, so nothing extra is needed on the host.
fix_dns() {
  local node=airbyte-abctl-control-plane k="kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system"
  for _ in $(seq 1 180); do
    docker exec "$node" $k get cm coredns >/dev/null 2>&1 && break
    sleep 5
  done
  docker exec "$node" sh -c "
    $k get cm coredns -o jsonpath='{.data.Corefile}' > /tmp/Corefile
    grep -q force_tcp /tmp/Corefile && exit 0
    sed -i 's|max_concurrent 1000|max_concurrent 1000\n       force_tcp|' /tmp/Corefile
    $k create cm coredns --from-file=Corefile=/tmp/Corefile --dry-run=client -o yaml | $k replace -f -
    $k rollout restart deploy/coredns" >/dev/null 2>&1 \
    && echo "pa-etl: CoreDNS set to use TCP upstream (Docker Desktop DNS workaround)"
}

case "${1:-}" in
  install)
    need_docker; ensure_abctl; check_linux
    args=(local install --port "$PORT" --insecure-cookies --no-browser)
    [[ "$LOW" == "1" ]] && args+=(--low-resource-mode)
    [[ -n "${AIRBYTE_HOST:-}" ]] && args+=(--host "$AIRBYTE_HOST")
    if [[ "$BRANDED" == "1" ]]; then
      write_values
      args+=(--values "$VALUES")
      echo "Installing with the PA ETL Airbyte server image: $SERVER_IMAGE"
    fi
    fix_dns &
    "$BIN" "${args[@]}"
    wait
    # Bring Airbyte back by itself after a reboot or a Docker restart (useful on a server).
    docker update --restart unless-stopped airbyte-abctl-control-plane >/dev/null 2>&1 \
      && echo "pa-etl: Airbyte will restart automatically with Docker"
    echo
    echo "Airbyte is on http://localhost:$PORT. Next: scripts/airbyte.sh credentials"
    ;;
  status)
    need_docker; ensure_abctl
    "$BIN" local status
    ;;
  credentials)
    ensure_abctl
    "$BIN" local credentials
    ;;
  env)
    ensure_abctl
    out="$("$BIN" local credentials 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
    cid="$(printf '%s\n' "$out" | awk -F': *' 'tolower($1) ~ /client-id/ {print $2}' | tr -d ' ')"
    sec="$(printf '%s\n' "$out" | awk -F': *' 'tolower($1) ~ /client-secret/ {print $2}' | tr -d ' ')"
    [[ -n "$cid" && -n "$sec" ]] || { echo "Could not read client credentials:"; echo "$out"; exit 1; }
    touch .env
    grep -v -E '^(AIRBYTE_CLIENT_ID|AIRBYTE_CLIENT_SECRET)=' .env > .env.tmp || true
    { cat .env.tmp; echo "AIRBYTE_CLIENT_ID=$cid"; echo "AIRBYTE_CLIENT_SECRET=$sec"; } > .env
    rm -f .env.tmp
    echo "Wrote AIRBYTE_CLIENT_ID and AIRBYTE_CLIENT_SECRET to .env. Run: docker compose up -d prefect-worker"
    ;;
  uninstall)
    need_docker; ensure_abctl
    "$BIN" local uninstall "${2:-}"
    ;;
  *)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
