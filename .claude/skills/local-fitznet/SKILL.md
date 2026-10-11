---
name: local-fitznet
description: Spin up or tear down the full local Fitz-Net stack for testing via this repo's docker-compose.yml - up, down, teardown-with-volumes - and the URLs to check. Use for local end-to-end testing of the core services.
---

# local-fitznet

`docker-compose.yml` in this repo runs the core stack: `gamerbell`,
`fitz-net-api`, `fitz-net-website`, `mongo`, and `caddy`
(`lucaslorentz/caddy-docker-proxy`, which routes by container labels).

## One-time prerequisites

```bash
docker network create fitznet          # external network the compose file expects
cp .env.example .env                   # then fill in secrets (see below)
```

Required `.env` keys: `MONGO_DATABASE`, `JWT_SECRET`, `ENCRYPTION_KEY`.

## Up

```bash
docker compose up -d
docker compose ps
docker compose logs -f fitz-net-api    # watch a service start
```

Images are pulled from Docker Hub (`mattlol85/*:latest`). To test a locally
built image, `docker build -t mattlol85/fitz-net-api:latest ../fitz-net-api`
first, then `docker compose up -d --force-recreate fitz-net-api`.

## URLs to check

Caddy serves by the hostnames in the compose labels; add them to your hosts file
pointing at `127.0.0.1`, or hit the containers directly:

| Service | Via Caddy label | Direct check |
|---|---|---|
| website | `fitznet.org`, `fitznet.doomdns.org` | `docker compose exec fitz-net-website wget -qO- localhost:80` |
| API | `api.fitznet.org` | `curl http://localhost` with Host header, or `docker compose exec fitz-net-api wget -qO- localhost:8080/actuator/health` |
| GamerBell | `gamerbell.fitznet.doomdns.org` | `.../actuator/health`, `/count` |
| MongoDB | — | `localhost:27017` (published) |

Quick health sweep:

```bash
for s in fitz-net-api gamerbell; do
  docker compose exec "$s" wget -qO- localhost:8080/actuator/health; echo
done
```

## Down (keep data)

```bash
docker compose down
```

## Teardown (drop volumes — wipes MongoDB + Caddy certs)

```bash
docker compose down -v
docker network rm fitznet     # only if you also want the network gone
```
