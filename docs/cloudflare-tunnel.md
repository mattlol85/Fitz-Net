# Cloudflare Tunnel

Goal: serve Fitz-Net through a Cloudflare Tunnel so the home router needs **no
open ports** and the home IP is never published. `cloudflared` (in
`docker-compose.yml`) dials out to Cloudflare; Cloudflare sends requests for the
tunnel's public hostnames down that connection to `http://caddy:80`.

```
Client ──https──▶ Cloudflare edge ──tunnel──▶ cloudflared ──http──▶ caddy:80 ──▶ service
```

## How it's wired

- **Tunnel:** `fitznet-proxmox`, remotely managed (hostname routes live in
  Zero Trust → Networks → Tunnels, not in a config file).
- **Token:** `CLOUDFLARE_TUNNEL_TOKEN` in the Docker VM's `.env`. Treat it as a
  secret. Rotate it from the tunnel's page if it leaks.
- **TLS:** Cloudflare terminates TLS. Tunnel-served sites are labelled
  `http://<host>` in Caddy. An `https` site would redirect the tunnel's plain
  HTTP request back to https and loop.
- **Zone SSL mode:** Full.

| Public hostname | Tunnel service | Caddy site |
|---|---|---|
| `gamerbell.fitznet.org` | `http://caddy:80` | `http://gamerbell.fitznet.org` (GamerBell `caddy_1`) |
| `fitznet.org` | `http://caddy:80` | `http://fitznet.org` (website `caddy_1`) |
| `api.fitznet.org` | `http://caddy:80` | `http://api.fitznet.org` (API `caddy_1`) |
| `lori.fitznet.org` | `http://caddy:80` | `http://lori.fitznet.org` (website `caddy_2`, Lori-Net) |
| `relay.fitznet.org` | `http://caddy:80` | `http://relay.fitznet.org` (`marine-park-relay`, Marine Park join codes) |

During the migration each service has **both** a legacy HTTPS site
(`caddy_0`) and a tunnel `http://` site (`caddy_1`). An explicit `http://`
site for a host stops Caddy's automatic HTTP→HTTPS redirect for that host. So:
- cloudflared's plain HTTP gets served instead of redirect-looping;
- Cloudflare → router:443 keeps working for any record not yet pointed at the
  tunnel.

That lets each DNS record flip with no downtime.

### Lori-Net (`lori.fitznet.org`)

Lori-Net is the website image again: the SPA picks the pink "LN" variant from
the hostname and gates the whole site on the `LORINET_ACCESS` permission. It
was born on the tunnel, so it only has an `http://` site (`caddy_2` on the
website service) and no legacy HTTPS site or doomdns name. Its Recipes tab
holds each user's private recipe book (served by the `/recipe-book`,
`/recipes` and `/recipe-images` REST and gRPC routes).

```sh
curl -si -H 'Host: lori.fitznet.org' http://127.0.0.1/ | head -1             # 200, not 308
curl -s  -H 'Host: lori.fitznet.org' http://127.0.0.1/manifest.json | grep Lori-Net
```

### Marine Park relay (`relay.fitznet.org`)

A WebSocket relay for the Marine Park game: hosts get a 6-character join code
and friends join by code, with every frame passing through the relay
(mattlol85/Marine-Park issue #2; source in its `Server/Relay/`). Tunnel-only
like Lori-Net. Cloudflare side, set up 2026-11-27:

- tunnel route `relay.fitznet.org` → `http://caddy:80`, before the catch-all;
- proxied `CNAME relay` → `<tunnel-id>.cfargotunnel.com`;
- Configuration Rule on that host: Browser Integrity Check off, Security Level
  essentially off. Game clients aren't browsers, so a challenge would silently
  break them (same reasoning as GamerBell).

The relay does its own rate limiting (rooms and join attempts per
`CF-Connecting-IP`), because the Free plan's one rate-limiting rule is already
used. Its Caddy site sets `reverse_proxy.stream_close_delay: 6h` so Caddy
reloads (any container change) don't drop games. Runbook:
[`marine-park-relay-vm-handoff.md`](marine-park-relay-vm-handoff.md).

```sh
curl -si -H 'Host: relay.fitznet.org' http://127.0.0.1/healthz | head -1     # 200, not 308
```

### Website and API

The website's nginx proxies `/api/*` to `http://fitz-net-api:8080` over the
Docker network. Browsers reach the API on the same origin, so moving
`fitznet.org` onto the tunnel moves most API traffic with it.

Steps, in order:
1. **VM:** deploy the compose file with the `caddy_1` sites. Check:
   ```sh
   curl -si -H 'Host: fitznet.org' http://127.0.0.1/ | head -1      # 200, not 308
   curl -si -H 'Host: api.fitznet.org' http://127.0.0.1/actuator/health | head -1
   ```
2. **Cloudflare:** point the `fitznet.org` CNAME at
   `<tunnel-id>.cfargotunnel.com`, proxied. It currently points at
   `fitznet.doomdns.org`. `api.fitznet.org` already points at the tunnel.
3. **Website repo:** move the browser-side URLs that still use doomdns to the
   `fitznet.org` hosts. These are the status dashboard's `API_CONFIGS` and
   `API_URLS.GAMERBELL`. Also point the nginx `/actuator-*` proxies at the
   internal services, so they stop going out through the router and back in.

## Cloudflare dashboard setup (phase 1 prep)

Do this before the [VM handoff](cloudflare-tunnel-vm-handoff.md).

1. **Turn on Zero Trust.** Open dash.cloudflare.com → Zero Trust. First time
   only: pick a team name and the **Free** plan. It may ask for a payment
   method, but the Free plan isn't charged.
2. **Create the tunnel.**
   - Go to Networks → Tunnels (or Connectors → Cloudflare Tunnels) → Create a
     tunnel → **Cloudflared**, and name it `fitznet-proxmox`.
   - On the install screen, pick **Docker** and copy **only the token**, the
     `eyJ…` string after `--token`. Store it in your password manager and
     hand it to the VM.
   - Don't run the shown command; the compose file runs the connector.
3. **Add the public hostname.** Click Next, or later open Tunnel →
   Public Hostname → Add:
   - Subdomain `gamerbell`, domain `fitznet.org`, path empty.
   - Service type **HTTP**, URL **`caddy:80`**.
   - Leave *Additional application settings* at their defaults. In particular,
     leave the HTTP Host Header blank, so Caddy sees `gamerbell.fitznet.org`
     and matches its site.
   - Saving creates a proxied `CNAME gamerbell → <tunnel-id>.cfargotunnel.com`.
     The tunnel shows *Inactive* until the VM starts `cloudflared`.
4. **Don't touch the apex record yet.** `fitznet.org` stays a CNAME to
   doomdns until phase 4.
5. **Check SSL/TLS.**
   - Overview should be **Full**. It already is.
   - Under Edge Certificates, turn on Always Use HTTPS, and keep Minimum TLS
     at 1.2. The ESP32 TLS stack is fine with 1.2, so don't force 1.3-only.
6. **Check Network.** WebSockets must be **On**. It's on by default.
7. **Keep bot protection off the bells.** The bells are non-browser clients
   (`ESP32HTTPClient`), and challenges silently break them.
   - Leave **Bot Fight Mode off**: on the Free plan it can't be bypassed per
     hostname.
   - Add a **Configuration Rule** (Rules → Configuration Rules): when
     *Hostname equals `gamerbell.fitznet.org`*, set Browser Integrity Check
     **Off** and Security Level **Essentially Off**.
   - Never enable *I'm Under Attack* on that hostname.
8. **Clean up records that leak the home IP** (check each one before
   deleting):
   - `logs.fitznet.org` and `mail.fitznet.org` are **DNS-only `A` records**
     that publish the home IP. That defeats the tunnel.
   - The mail stack was dropped, so `mail` A, the apex `MX` and the apex
     `v=spf1 mx` TXT can likely go.
   - For `logs`, either delete it or later route it through the tunnel behind
     Cloudflare Access.
   - Keep the `send.` / `resend._domainkey` records if the API still sends
     email through Resend.

`api.fitznet.org` has no DNS record today even though Caddy lists it. It joins
the tunnel in phase 4.

## Migration (bells first)

Bells on firmware ≤ v0.16.0 only know `gamerbell.fitznet.doomdns.org`, which
isn't a Cloudflare domain and so can't be tunnelled. If that path is closed
before they update, they go offline and can't receive the fix over the air.

1. **Dual path.** Create the tunnel and route `gamerbell.fitznet.org`. Keep the
   doomdns Caddy site and the router forwards. Verify:
   ```sh
   curl -si -H 'x-ESP32-version: v0.16.0' https://gamerbell.fitznet.org/api/firmware/latest | head -1
   ```
2. **Fallback firmware.** From v0.17.0 the bell tries `gamerbell.fitznet.org`
   first and falls back to the doomdns host after repeated failures. It
   remembers the last host that worked in NVS. Release it; bells pick it up within
   about a minute (OTA check at boot and every 60 s).
3. **Soak.** In Grafana, confirm every known `deviceMac` reports v0.17.0 or later.
   Bells that are powered off still run old firmware. Keep the old path for a
   couple of weeks, or until every MAC has checked in.
4. **Close the old path.** Done 2026-11-18 without waiting for the bells, by
   choice. Bells on ≤ v0.16.0 go offline and need a USB reflash. Steps:
   [`cloudflare-tunnel-close-ports-handoff.md`](cloudflare-tunnel-close-ports-handoff.md).
   - **Close only router 80/443** (to the Docker VM).
   - **Keep the DDNS updater and `fitznet.doomdns.org`.** OpenVPN (AI worker
     nodes, UDP to the Pi) and the `generate-ai-node-package` workflow (SSH
     :22) still use that hostname. Those forwards stay open.
   - Existing AI nodes must have `apiBaseUrl` in `node.json` changed to
     `https://api.fitznet.org` first
     ([`scripts/ai-node-installer`](../scripts/ai-node-installer/README.md)).
   - `logs.fitznet.org` (Grafana) moves to the tunnel too, as a proxied CNAME
     plus an `http://` Caddy site. Put Cloudflare Access in front of it next.
