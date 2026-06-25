# Fitz-Net Workspace — Agentic Development Guide

This repo is the **orchestration hub** for the Fitz-Net platform. It contains GitHub Actions workflows for cross-repo automation and a sandbox for agentic development. There is no application code here.

---

## Platform Overview

Fitz-Net is a personal full-stack platform consisting of six sibling repositories:

| Repo | Path | Role | Stack |
|---|---|---|---|
| **Fitz-Net** (this repo) | `../Fitz-Net` | Orchestration hub, GitHub Actions, agentic sandbox | Markdown, YAML |
| **fitz-net-api** | `../fitz-net-api` | REST API backend | Java 21, Spring Boot 3.4, Gradle, MongoDB |
| **fitz-net-website** | `../fitz-net-website` | React SPA frontend | React 19, Vite, React Router v7 |
| **GamerBell** | `../GamerBell` | WebSocket relay + OTA firmware server | Java 21, Spring Boot 3.4, Gradle |
| **Esp32FitznetBell** | `../Esp32FitznetBell` | ESP32 bell button firmware (talks to GamerBell over WebSocket, OTA-updated) | C++, PlatformIO, Arduino |
| **Fitz-Bot** | `../Fitz-Bot` | Discord bot — voice-join milestones, media downloads (Radarr/Sonarr), Minecraft whitelist management over RCON | Java 21, Spring Boot 3.2, Gradle, JDA |

For deep development context on each repo, see their individual `.github/agents.md` files.

---

## Before You Start

**ALWAYS sync the latest changes in every sibling repo before doing any work.** These repos move independently, so working against stale checkouts leads to conflicts and broken cross-repo contracts. Run `git pull` in each of the six paths first:

```bash
git -C ../Fitz-Net pull
git -C ../fitz-net-api pull
git -C ../fitz-net-website pull
git -C ../GamerBell pull
git -C ../Esp32FitznetBell pull
git -C ../Fitz-Bot pull
```

Only begin your task once all six repos are up to date.

---

## This Repo's Responsibilities

- **GitHub Actions workflows** — Cross-repo orchestration (triggering builds, coordinating releases across repos)
- **Fitz-Net-Agent-Sandbox/** — Shared agent instructions and cross-repo feature development guide
- **Documentation** — Platform-level README and architecture context

---

## Cross-Repo Feature Development

When building a feature that spans multiple repos:

1. Create matching feature branches in each affected repo: `feature/FEATURENAME`
2. Define the API contract first (request/response shape) before writing any code
3. Implement backend (`fitz-net-api`) before frontend (`fitz-net-website`)
4. For GamerBell/WebSocket changes: update `ButtonEventDto` and the corresponding `WebSocketButton.jsx` in `fitz-net-website` in sync
5. For ESP32 bell changes: the `Esp32FitznetBell` firmware (`src/main.cpp`) speaks the same WebSocket event schema as GamerBell — keep the press/release payload aligned. Firmware is delivered to devices over the air via GamerBell's `GET /api/firmware/latest`, which pulls `.bin` artifacts from `Esp32FitznetBell` GitHub Releases.
6. For Fitz-Bot / Minecraft changes: `Fitz-Bot` manages the Minecraft server (running on a separate VM adjacent to the Docker host) over **RCON**. Slash commands live in `src/main/java/org/fitznet/commands/` and are registered in `BotService.startBot()`. Keep the `MINECRAFT_RCON_*` config in sync with the server's `server.properties`. See [`docs/fitz-bot.md`](../docs/fitz-bot.md).
7. See `Fitz-Net-Agent-Sandbox/AGENT_INSTRUCTIONS.md` for the full cross-repo workflow and pitfall reference

---

## GitHub Actions

Workflows live in `.github/workflows/`. This hub can trigger workflows in sibling repos via `repository_dispatch` or `workflow_dispatch` events.

---

## Commit Convention

```
feat(subject): description
fix(subject): description
chore(subject): description
```
