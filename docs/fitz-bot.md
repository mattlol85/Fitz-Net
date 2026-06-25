# Fitz-Bot — Discord Bot & Minecraft Whitelist

**Fitz-Bot** ([mattlol85/Fitz-Bot](https://github.com/mattlol85/Fitz-Bot)) is the Discord bot for the Fitz-Net community. It is a standalone **Java 21 / Spring Boot 3.2** service built on **JDA 5** that:

- tracks voice-channel activity and posts milestone celebrations,
- exposes media-download commands backed by **Radarr/Sonarr** (the "JoeNet" integration), and
- manages the **Minecraft server** — adding players to the whitelist on demand via `/whitelist`.

Unlike the core services, Fitz-Bot has no Docker artifact in its repo today; it runs as a Spring Boot process and connects outward to Discord and to the Minecraft server.

---

## Architecture

The Minecraft server runs on its **own VM**, adjacent to the Docker host VM. Fitz-Bot reaches it over the **RCON** protocol (Minecraft's remote console) — no shared filesystem or SSH required.

```
Discord  ──slash commands──►  Fitz-Bot (Spring Boot + JDA)
                                  │
                                  │  RCON (TCP :25575)
                                  ▼
                       Minecraft Server VM
                       (white-list + online-mode)
```

When a trusted member runs `/whitelist <username>`, Fitz-Bot opens an RCON connection and sends `whitelist add <username>`. The server validates the name against Mojang auth (because `online-mode=true`) and adds it to `whitelist.json`.

---

## Why this stops crawlers

The user observed anonymous bots/crawlers connecting to the Minecraft server. The lockdown is **server-side configuration**; the `/whitelist` command simply manages *who is allowed in*. In `server.properties` on the Minecraft VM:

```properties
white-list=true
enforce-whitelist=true   # kicks already-connected non-whitelisted players
online-mode=true         # validates usernames against Mojang auth — fake/crawler accounts can't join
enable-rcon=true
rcon.port=25575
rcon.password=<strong-secret>
```

- `white-list=true` blocks anyone not on the list.
- `online-mode=true` means only real, authenticated Mojang/Microsoft accounts can connect — cracked/anonymous crawler clients are rejected outright.
- `enable-rcon` + `rcon.password` allow Fitz-Bot to manage the list remotely.

Restart the Minecraft server after editing `server.properties`.

---

## Slash commands

| Command | Who | Purpose |
|---|---|---|
| `/whitelist <username>` | Members with the configured role | Add a player to the Minecraft whitelist over RCON |
| `/setwhitelistrole <role>` | Admin (Manage Server) | Choose which Discord role may use `/whitelist` |
| `/setbotchannel` · `/getbotchannel` | Admin | Configure where milestone messages post |
| `/joenet download` · `/joenet status` | Members | Search/queue movies & TV via Radarr/Sonarr |

`/whitelist` is **role-gated**: only members holding the role set by `/setwhitelistrole` (admins always allowed) can add players. The username is validated against Minecraft's rules (`^[A-Za-z0-9_]{3,16}$`) before being sent, which also prevents RCON command injection.

---

## Configuration

Fitz-Bot reads configuration from `application.properties` with environment-variable overrides:

| Variable | Default | Purpose |
|---|---|---|
| `DISCORD_BOT_TOKEN` | — | Discord bot token |
| `MINECRAFT_RCON_HOST` | — | Hostname/IP of the Minecraft VM |
| `MINECRAFT_RCON_PORT` | `25575` | RCON port (matches `rcon.port`) |
| `MINECRAFT_RCON_PASSWORD` | — | RCON password (matches `rcon.password`) |
| `JOENET_HOST`, `JOENET_RADARR_APIKEY`, `JOENET_SONARR_APIKEY` | — | Radarr/Sonarr media integration |

---

## Setup checklist

1. On the Minecraft VM, set the `server.properties` values above and restart the server.
2. Make sure RCON port `25575` is reachable from wherever Fitz-Bot runs (firewall / VM network).
3. Set `MINECRAFT_RCON_HOST` / `MINECRAFT_RCON_PORT` / `MINECRAFT_RCON_PASSWORD` in Fitz-Bot's environment.
4. Start the bot (`./gradlew bootRun`); it auto-registers slash commands.
5. In Discord, run `/setwhitelistrole @Trusted` (as an admin), then have a member with that role run `/whitelist <username>`.
