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
#           PA_ETL_HOME (~/.pa-etl, where abctl is kept)
set -euo pipefail
cd "$(dirname "$0")/.."

ABCTL_VERSION="${ABCTL_VERSION:-v0.30.4}"
PORT="${AIRBYTE_PORT:-8000}"
LOW="${AIRBYTE_LOW_RESOURCE:-1}"
HOME_DIR="${PA_ETL_HOME:-$HOME/.pa-etl}"
BIN="$HOME_DIR/bin/abctl-$ABCTL_VERSION"
export DO_NOT_TRACK=1

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

case "${1:-}" in
  install)
    need_docker; ensure_abctl
    args=(local install --port "$PORT" --insecure-cookies --no-browser)
    [[ "$LOW" == "1" ]] && args+=(--low-resource-mode)
    "$BIN" "${args[@]}"
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
