# Fitz-Net Workspace — Agentic Development Guide

This repo is the **orchestration hub** for the Fitz-Net platform. It contains GitHub Actions workflows for cross-repo automation and a sandbox for agentic development. There is no application code here.

---

## Platform Overview

Fitz-Net is a personal full-stack platform consisting of five sibling repositories:

| Repo | Path | Role | Stack |
|---|---|---|---|
| **Fitz-Net** (this repo) | `../Fitz-Net` | Orchestration hub, GitHub Actions, agentic sandbox | Markdown, YAML |
| **fitz-net-api** | `../fitz-net-api` | REST API backend | Java 21, Spring Boot 3.4, Gradle, MongoDB |
| **fitz-net-website** | `../fitz-net-website` | React SPA frontend | React 19, Vite, React Router v7 |
| **GamerBell** | `../GamerBell` | WebSocket relay + OTA firmware server | Java 21, Spring Boot 3.4, Gradle |
| **Esp32FitznetBell** | `../Esp32FitznetBell` | ESP32 bell button firmware (talks to GamerBell over WebSocket, OTA-updated) | C++, PlatformIO, Arduino |

For deep development context on each repo, see their individual `.github/agents.md` files.

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
6. See `Fitz-Net-Agent-Sandbox/AGENT_INSTRUCTIONS.md` for the full cross-repo workflow and pitfall reference

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
