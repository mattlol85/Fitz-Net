#!/bin/bash
# Runs once, automatically, when the mongo container starts against an empty
# /data/db (the official mongo image sources every /docker-entrypoint-initdb.d/*.sh
# script after the root user from MONGO_INITDB_ROOT_USERNAME/PASSWORD is created).
# Creates a readWrite-only app user scoped to MONGO_INITDB_DATABASE so fitz-net-api
# never connects as root.
set -e

mongosh admin --host localhost -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --eval "
  db.getSiblingDB('$MONGO_INITDB_DATABASE').createUser({
    user: '$MONGO_APP_USERNAME',
    pwd: '$MONGO_APP_PASSWORD',
    roles: [{ role: 'readWrite', db: '$MONGO_INITDB_DATABASE' }]
  })
"
