#!/bin/bash
# Build the three PA ETL images, tag them with the version and :latest, and
# optionally push or save them.
#   scripts/build-images.sh                 build only
#   scripts/build-images.sh --push          also push (docker login first)
#   scripts/build-images.sh --save out.tar  also write one tar for offline use
# The image prefix comes from PA_IMAGE_PREFIX (default pa-etl), e.g.
#   PA_IMAGE_PREFIX=ghcr.io/your-org/pa-etl scripts/build-images.sh --push
set -euo pipefail
cd "$(dirname "$0")/.."

PREFIX="${PA_IMAGE_PREFIX:-pa-etl}"
VERSION="${PA_VERSION:-$(cat VERSION)}"
export PA_IMAGE_PREFIX="$PREFIX" PA_VERSION="$VERSION"
IMAGES=(prefect gateway)
AIRBYTE_TAG="${AIRBYTE_TAG:-$(grep -E '^AIRBYTE_TAG=' .env.example | cut -d= -f2)}"

docker compose build --pull prefect-server gateway
for name in "${IMAGES[@]}"; do
  docker tag "$PREFIX/$name:$VERSION" "$PREFIX/$name:latest"
done
# The Airbyte image is versioned by the Airbyte release it is built on, not by PA ETL's version.
docker build --pull -f airbyte/Dockerfile --build-arg "AIRBYTE_TAG=$AIRBYTE_TAG" \
  -t "$PREFIX/airbyte-server:$AIRBYTE_TAG" -t "$PREFIX/airbyte-server:latest" .
echo "Built: $(printf "$PREFIX/%s:$VERSION " "${IMAGES[@]}") $PREFIX/airbyte-server:$AIRBYTE_TAG"

case "${1:-}" in
  --push)
    for name in "${IMAGES[@]}"; do
      docker push "$PREFIX/$name:$VERSION"
      docker push "$PREFIX/$name:latest"
    done
    docker push "$PREFIX/airbyte-server:$AIRBYTE_TAG"
    docker push "$PREFIX/airbyte-server:latest" ;;
  --save)
    out="${2:?usage: --save file.tar}"
    docker save -o "$out" $(for n in "${IMAGES[@]}"; do echo "$PREFIX/$n:$VERSION"; done) "$PREFIX/airbyte-server:$AIRBYTE_TAG"
    echo "Saved $out. On another machine: docker load -i $out" ;;
esac
