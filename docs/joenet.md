# Joenet admin panel

The **Joenet** tab on the website has an **Admin Panel** sub-tab: a Fitz-Net-themed UI for the Radarr and Sonarr v3 APIs. `/joenet` itself is a "Coming soon" placeholder for a future API integration.

## How it works

```
browser ──HTTPS──> fitz-net-api  /joenet/{radarr|sonarr}/**  ──HTTP──> ${JOENET_HOST}:7878 | :8989  /api/v3/**
          JWT + X-Joenet-Key        (permission check, fixed host)        X-Api-Key
```

Radarr and Sonarr are plain-HTTP, LAN-only services with no CORS headers, so the browser cannot call them directly from the HTTPS site. `fitz-net-api` forwards the request instead.

- The API host comes from `JOENET_HOST` and defaults to `joenet.doomdns.org` (the same host Fitz-Bot uses), so no setup is needed unless it moves. Ports are `7878` (Radarr) and `8989` (Sonarr). If `JOENET_HOST` is set empty the proxy returns `503`.
- The Radarr/Sonarr API key is pasted into the Admin Panel. The site verifies it with `GET /joenet/{app}/system/status` and only then saves it, in `sessionStorage` (gone when the tab closes, on logout, or on a `401`).
- The key is sent per request in the `X-Joenet-Key` header and forwarded as `X-Api-Key`. The API never stores or logs it.

## Access

The tab and the proxy require the `JOENET_USER` permission (or `ADMIN`). `JOENET_USER` is a runtime permission stored in Mongo — create it and grant it to users from the `/admin` page (see the permissions section of the README).

## Setup on the prod box

1. Nothing to set: `JOENET_HOST` defaults to `joenet.doomdns.org`. Only add `JOENET_HOST=<host>` to the Docker VM's `.env` (and redeploy `fitz-net-api`) to override it.
2. Confirm the VM can reach it: `curl -H "X-Api-Key: <key>" http://joenet.doomdns.org:7878/api/v3/system/status`.
3. Make sure `JOENET_USER` exists and is granted to your user.

## Proxy contract

`{GET,POST,PUT,DELETE} /joenet/{app}/{path}?query` — `app` is `radarr` or `sonarr`.

| Status | Meaning |
|---|---|
| upstream status | Passed through, including upstream `401` for a bad key |
| `400` | Missing `X-Joenet-Key`, or an invalid path (`..`, encoded traversal, empty) |
| `403` | Caller lacks `JOENET_USER` / `ADMIN` |
| `404` | Unknown `app` |
| `502` | `JOENET_HOST` unreachable |
| `503` | `JOENET_HOST` not configured |
