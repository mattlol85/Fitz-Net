# Handoff: migrating the production `mongo` container to an authenticated, supported version

This is the runbook for the host running `docker-compose.yml` (the Fitz-Net VM) for cutting the existing `mongo:4.4`, unauthenticated, host-published container over to the `mongo:8.0`, authenticated, internal-network-only setup introduced in [#40](https://github.com/mattlol85/Fitz-Net/issues/40). Run this by hand on that host — it can't be done from a dev checkout.

## Why a separate runbook

The live `mongo_data` volume holds real user accounts (emails, BCrypt hashes). Swapping `image: mongo:4.4` for `image: mongo:8.0` in place against that volume isn't safe — MongoDB only supports upgrading one major version at a time (4.4→5.0→6.0→7.0→8.0), bumping `setFeatureCompatibilityVersion` at every hop. Doing that against production data is fragile and easy to get wrong. A `mongodump`/`mongorestore` into a fresh container sidesteps all of it — the dump format isn't tied to the on-disk engine version.

## Steps

1. **Back up the existing data** (still running as `mongo:4.4`, unauthenticated):
   ```bash
   docker exec fitz-net-api-mongo mongodump --out /tmp/mongo-backup
   docker cp fitz-net-api-mongo:/tmp/mongo-backup ./mongo-backup-$(date +%Y%m%d)
   ```
   Copy `./mongo-backup-<date>/` somewhere off the box too (it's the only copy of user data until step 5 is verified).

2. **Generate credentials** and add them to `.env` on the host (not committed anywhere):
   ```
   MONGO_INITDB_ROOT_USERNAME=<new root user>
   MONGO_INITDB_ROOT_PASSWORD=<strong random password>
   MONGO_APP_USERNAME=<app user, e.g. fitznet-api>
   MONGO_APP_PASSWORD=<strong random password>
   ```

3. **Stop the old container and clear its volume** (the backup from step 1 is the safety net — don't skip step 1):
   ```bash
   docker compose stop mongo
   docker compose rm -f mongo
   docker volume rm fitz-net_mongo_data   # confirm the actual volume name with `docker volume ls` first
   ```

4. **Pull the updated `docker-compose.yml`** (this PR) and bring the new `mongo:8.0` container up on the now-empty volume:
   ```bash
   git pull
   docker compose up -d mongo
   docker compose logs mongo   # confirm create-app-user.sh ran without error
   ```

5. **Restore the data** into the new, authenticated instance:
   ```bash
   docker cp ./mongo-backup-<date> fitz-net-api-mongo:/tmp/mongo-backup
   docker exec fitz-net-api-mongo mongorestore \
     -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
     /tmp/mongo-backup
   ```

6. **Bring up the rest of the stack** and verify end to end:
   ```bash
   docker compose up -d
   docker compose logs fitz-net-api   # confirm it connects successfully
   ```
   Then confirm login/registration works on the live site, and that another host on the LAN can no longer reach port 27017 (`nc -z <vm-lan-ip> 27017` should now fail/time out).

7. **Clean up** once you're confident the new instance is healthy: delete `./mongo-backup-<date>/` and the on-host `/tmp/mongo-backup` copies (they contain plaintext-adjacent BCrypt-hashed user data — don't leave them lying around longer than needed).
