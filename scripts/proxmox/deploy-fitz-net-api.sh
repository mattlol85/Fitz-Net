#!/usr/bin/env bash
set -euo pipefail

SERVICE="fitz-net-api"
IMAGE="mattlol85/fitz-net-api"
COMPOSE_DIR="/opt/fitznet"
TAG="${1:-latest}"

echo "Deploying ${SERVICE} with tag: ${TAG}"

docker pull "${IMAGE}:${TAG}"

if [ "${TAG}" != "latest" ]; then
  docker tag "${IMAGE}:${TAG}" "${IMAGE}:latest"
fi

cd "${COMPOSE_DIR}"
docker compose up -d --no-deps "${SERVICE}"

docker image prune -f

echo "Deploy of ${SERVICE} complete (tag: ${TAG})"
