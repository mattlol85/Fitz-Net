#!/usr/bin/env bash
# Deploys the Marine Park WebSocket relay (relay.fitznet.org, Marine-Park issue #2).
#
# Usage: deploy-marine-park-relay.sh [tag]     # tag defaults to latest, e.g. sha-1a2b3c4
#
# Recreating the container closes every open game (clients see "Host ended the session"),
# so it says how many rooms are open before it does that.
set -euo pipefail

SERVICE="marine-park-relay"
IMAGE="mattlol85/marine-park-relay"
COMPOSE_DIR="/opt/fitznet"
TAG="${1:-latest}"

echo "Deploying ${SERVICE} with tag: ${TAG}"

docker pull "${IMAGE}:${TAG}"

if [ "${TAG}" != "latest" ]; then
  docker tag "${IMAGE}:${TAG}" "${IMAGE}:latest"
fi

# Best effort: the metrics port is only reachable inside the container's network namespace.
if docker ps --format '{{.Names}}' | grep -qx "${SERVICE}"; then
  rooms="$(docker exec "${SERVICE}" wget -q -O - http://127.0.0.1:9464/metrics 2>/dev/null \
    | awk '/^marinepark_relay_rooms[ {]/ { print $NF; exit }' || true)"
  echo "Open rooms before restart: ${rooms:-unknown} (they will be closed)"
fi

cd "${COMPOSE_DIR}"
docker compose up -d --no-deps "${SERVICE}"

# The image's HEALTHCHECK probes /healthz every 30s, so the first result can take ~30s.
# Wait up to 90s for it rather than reporting success blind.
status="starting"
for _ in $(seq 1 45); do
  status="$(docker inspect --format '{{.State.Health.Status}}' "${SERVICE}" 2>/dev/null || echo missing)"
  if [ "${status}" = "healthy" ]; then
    break
  fi
  sleep 2
done

if [ "${status}" != "healthy" ]; then
  echo "ERROR: ${SERVICE} is ${status} after 90s. Last logs:" >&2
  docker logs --tail 50 "${SERVICE}" >&2 || true
  exit 1
fi

docker image prune -f

echo "Deploy of ${SERVICE} complete (tag: ${TAG})"
