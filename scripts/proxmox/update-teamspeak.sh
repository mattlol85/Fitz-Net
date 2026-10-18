#!/usr/bin/env bash
set -euo pipefail

SERVICE="teamspeak"
COMPOSE_DIR="${COMPOSE_DIR:-/home/deploy/teamspeak}"

cd "${COMPOSE_DIR}"

BEFORE="$(docker inspect --format '{{.Image}}' "${SERVICE}" 2>/dev/null || echo none)"

# pull_policy: always fetches the newest :latest; up -d only recreates the
# container if the image actually changed.
docker compose up -d "${SERVICE}"

AFTER="$(docker inspect --format '{{.Image}}' "${SERVICE}")"

if [ "${BEFORE}" != "${AFTER}" ]; then
  echo "Updated ${SERVICE}: ${BEFORE} -> ${AFTER}"
  docker image prune -f
else
  echo "${SERVICE} already on latest image (${AFTER})"
fi
