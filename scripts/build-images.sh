#!/bin/bash
# Build the two PA ETL images, tag them with the version and :latest, and
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

docker compose build --pull prefect-server gateway
for name in "${IMAGES[@]}"; do
  docker tag "$PREFIX/$name:$VERSION" "$PREFIX/$name:latest"
done
echo "Built: $(printf "$PREFIX/%s:$VERSION " "${IMAGES[@]}")"

case "${1:-}" in
  --push)
    for name in "${IMAGES[@]}"; do
      docker push "$PREFIX/$name:$VERSION"
      docker push "$PREFIX/$name:latest"
    done ;;
  --save)
    out="${2:?usage: --save file.tar}"
    docker save -o "$out" $(for n in "${IMAGES[@]}"; do echo "$PREFIX/$n:$VERSION"; done)
    echo "Saved $out. On another machine: docker load -i $out" ;;
esac
