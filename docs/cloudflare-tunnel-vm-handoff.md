# Handoff: Cloudflare Tunnel connector on the Proxmox Docker VM

Do this on the Proxmox-hosted Docker VM (`192.168.1.59`, alias `proxmoxvm`,
compose dir `/opt/fitznet`). It is **phase 1** of
[`cloudflare-tunnel.md`](cloudflare-tunnel.md): add a second path to GamerBell
through a Cloudflare Tunnel **alongside** the existing setup.

## What you're doing, and what you're not

**Do:**
- Run a `cloudflared` container.
- Serve `gamerbell.fitznet.org` through it.

**Do not, under any circumstances in this handoff:**
- Close router ports 80/443.
- Remove the `80:80` / `443:443` port publishing from Caddy.
- Remove `gamerbell.fitznet.doomdns.org` or `fitznet.doomdns.org`.
- Stop the DDNS updater.

The ESP32 bells on firmware ≤ v0.16.0 only know the doomdns hostname. Breaking
that path strands them with no way to receive an OTA fix.

## Before you start

You need these from Matt:
1. **The tunnel token** for the `fitznet-proxmox` tunnel. It starts with
   `eyJ`. Get it from Zero Trust → Networks → Tunnels → `fitznet-proxmox` →
   Configure → Docker command. It's the value after `--token`.
   - It's a secret. Don't paste it into logs, chat, issues or git.
   - If it leaks, rotate it from that page.
2. **Confirmation that the tunnel's public hostname exists:**
   `gamerbell.fitznet.org` → `http://caddy:80`.

## 1. Update the compose file

Bring `/opt/fitznet` up to date with Fitz-Net `main`, after the
`cloudflare-tunnel` PR is merged. If `/opt/fitznet` isn't a git checkout, copy
the new `docker-compose.yml` over the old one.

```bash
cd /opt/fitznet
cp docker-compose.yml docker-compose.yml.bak-$(date +%F)   # rollback copy
git pull            # or copy the file from the merged PR
```

The merged file has two changes:
- **GamerBell labels.** GamerBell now has two Caddy sites:
  - `caddy_0`: `gamerbell.fitznet.doomdns.org`, the existing HTTPS site.
  - `caddy_1`: `http://gamerbell.fitznet.org`, the tunnel site. It's plain
    HTTP on purpose, because Cloudflare does TLS.
- **New `cloudflared` service.** It runs on the `fitznet` network, uses image
  `cloudflare/cloudflared:2026.10.7`, and reads `CLOUDFLARE_TUNNEL_TOKEN`.

## 2. Add the token to `.env`

```bash
cd /opt/fitznet
grep -q '^CLOUDFLARE_TUNNEL_TOKEN=' .env || echo 'CLOUDFLARE_TUNNEL_TOKEN=' >> .env
nano .env           # paste the token after CLOUDFLARE_TUNNEL_TOKEN=
chmod 600 .env
```

## 3. Bring it up

```bash
cd /opt/fitznet
docker compose config -q                 # must print nothing
docker compose pull cloudflared
docker compose up -d gamerbell cloudflared
```

Recreating `gamerbell` applies the new labels. Bells reconnect on their own
within about 5 seconds. Caddy reloads its config from the labels; it doesn't
need restarting.

## 4. Verify

All of these must pass.

```bash
# a) cloudflared is connected. Expect 4 "Registered tunnel connection" lines.
docker logs cloudflared 2>&1 | grep -c "Registered tunnel connection"

# b) Caddy serves the tunnel site over plain HTTP with no redirect.
#    Expect 304 (or 200 with a .bin if a newer release exists), NOT 301/308.
docker exec cloudflared wget -qS -O /dev/null \
  --header='Host: gamerbell.fitznet.org' --header='x-ESP32-version: v0.16.0' \
  http://caddy:80/api/firmware/latest 2>&1 | grep 'HTTP/'
# (If the image has no wget, run the same request with curl from the host:
#  curl -si -H 'Host: gamerbell.fitznet.org' -H 'x-ESP32-version: v0.16.0' http://127.0.0.1/api/firmware/latest | head -1)

# c) End to end through Cloudflare. Expect HTTP/2 304.
curl -si -H 'x-ESP32-version: v0.16.0' https://gamerbell.fitznet.org/api/firmware/latest | head -1

# d) WebSocket upgrade works through the tunnel. Expect HTTP/1.1 101.
curl -si --http1.1 -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://gamerbell.fitznet.org/ws | head -1

# e) The OLD path still works. Expect 304. This is the one that matters most.
curl -si -H 'x-ESP32-version: v0.16.0' https://gamerbell.fitznet.doomdns.org/api/firmware/latest | head -1

# f) The bells are still online. GamerBell should show recent connections.
docker logs --since 5m gamerbell 2>&1 | grep -iE "connect|firmware update check" | tail
```

If (d) returns 403, GamerBell is rejecting the request's `Origin`. Report it
rather than loosening `cors.allowed-origins`. Bells don't send a browser
`Origin`, so they're unaffected.

## Rollback

`cloudflared` can't affect the old path, so rolling back is safe at any time:

```bash
cd /opt/fitznet
docker compose stop cloudflared
cp docker-compose.yml.bak-<date> docker-compose.yml && docker compose up -d gamerbell
```

## Report back

Send Matt:
- the result line of each check, a) to f);
- the `cloudflared` image version that's running;
- anything unexpected in `docker logs cloudflared`.

Never include the token.
