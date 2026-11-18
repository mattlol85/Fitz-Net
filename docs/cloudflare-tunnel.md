# Cloudflare Tunnel

Goal: serve Fitz-Net through a Cloudflare Tunnel so the home router needs **no
open ports** and the home IP is never published. `cloudflared` (in
`docker-compose.yml`) dials out to Cloudflare; Cloudflare sends requests for the
tunnel's public hostnames down that connection to `http://caddy:80`. On the
VM the stack actually runs from `/opt/fitznet/compose.yml`, which has drifted
from the repo file; port changes into it by hand.

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

Each service keeps its HTTPS sites in `caddy_0` (the doomdns hosts, plus
`fitznet.org` for Cloudflare's proxied-to-origin path) until phase 4. An
explicit `http://` site stops Caddy's automatic http→https redirect for that
host, so the HTTPS and tunnel sites for `fitznet.org` coexist.

### Real client IPs

Caddy's global `servers` options are set as labels on the `caddy` service:
- **`trusted_proxies`:** the `fitznet` Docker network, i.e. `cloudflared`,
  written as CIDRs that leave out the gateway `172.18.0.1`, plus Cloudflare's
  edge ranges from <https://www.cloudflare.com/ips/>.
- **`client_ip_headers`:** `Cf-Connecting-IP`, then `X-Forwarded-For`.

**Why the gateway is excluded:** Docker's port proxy forwards some outside
traffic from `172.18.0.1`, so trusting it would let anyone forge
`Cf-Connecting-IP` by sending straight to the origin.

**What it gives you:** upstreams get the real client first in
`X-Forwarded-For`. GamerBell's `clientIp` and the website's nginx log show
the visitor's IP. The API doesn't log client IPs.

**Upkeep:** refresh the Cloudflare ranges if Cloudflare changes them. Once
phase 4 closes the origin's ports, only the Docker ranges matter.

**Verify** (2026-11-18): a tunnel request logs the caller's public IP, not
`cloudflared`'s, and a spoofed `Cf-Connecting-IP` sent to the doomdns host is
ignored.

### Status (2026-11-18)

- **`gamerbell.fitznet.org`:** live on the tunnel.
- **`api.fitznet.org`:** live on the tunnel. It has no other route.
- **`fitznet.org`:** has a tunnel route, but its apex DNS record still sent
  traffic to the origin's port 443. Replace the apex record with the tunnel
  route. The site works either way.

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
4. **Route `fitznet.org` and `api.fitznet.org` too** (done 2026-11-18). Same
   settings as `gamerbell`. The apex `fitznet.org` must point at the tunnel,
   replacing its old proxied CNAME to doomdns.
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
   - The mail stack is gone. On 2026-11-18 its containers (`mailserver`,
     `roundcube`) and the `mail_roundcube-data` volume were removed from the
     VM. So the `mail` A, the apex `MX` and the apex `v=spf1 mx` TXT can go,
     along with router forwards for ports 25, 465, 587 and 993.
     `/home/deploy/mail/` still holds the old compose file and data, owned by
     `deploy` and root; delete it with `sudo rm -rf /home/deploy/mail`.
   - For `logs`, either delete it or later route it through the tunnel behind
     Cloudflare Access.
   - Keep the `send.` / `resend._domainkey` records if the API still sends
     email through Resend.

`fitznet.org` and `api.fitznet.org` were moved to the tunnel on 2026-11-18,
ahead of phase 4, because they don't depend on the bells.

## Migration (bells first)

Bells on firmware ≤ v0.16.0 only know `gamerbell.fitznet.doomdns.org`, which
isn't a Cloudflare domain and so can't be tunnelled. If that path is closed
before they update, they go offline and can't receive the fix over the air.

1. **Dual path.** Create the tunnel and route `gamerbell.fitznet.org`. Keep the
   doomdns Caddy site and the router forwards. Verify:
   ```sh
   curl -si -H 'x-ESP32-version: v0.16.0' https://gamerbell.fitznet.org/api/firmware/latest | head -1
   ```
2. **Fallback firmware.** Released as **v0.17.0** on 2026-11-18
   (Esp32FitznetBell #25).
   - **Host order:** the bell tries `gamerbell.fitznet.org` first. It moves to
     the next host after 30 s with Wi-Fi up but no WebSocket.
   - **Why a timer:** a failed connect fires no event in the WebSocket
     library, so counting failures would miss it.
   - **Memory:** it saves the last host that worked in NVS
     (`app-config/hostIdx`), so a reboot starts there.
   - **Grafana:** it logs `Connected via host …` and `Failover A -> B` to
     GamerBell's `/api/devices/log`.
   - **Rollout:** bells pick it up within about a minute of coming online (OTA
     check at boot and every 60 s), over either host.
3. **Soak.** In Grafana, confirm every known `deviceMac` reports v0.17.0 or later.
   Bells that are powered off still run old firmware. Keep the old path for a
   couple of weeks, or until every MAC has checked in.
4. **Close the old path.** `fitznet.org` and `api.fitznet.org` are already on
   the tunnel. Drop the doomdns sites and the HTTPS `fitznet.org` site (each
   service's `caddy_0`), remove the `80`/`443`
   port publishing on Caddy, close the router forwards and stop the DDNS
   updater. Remove or proxy any DNS-only `A` records that still expose the
   home IP.
