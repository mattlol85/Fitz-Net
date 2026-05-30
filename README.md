<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a name="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![LinkedIn][linkedin-shield]][linkedin-url]



<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/mattlol85/Fitz-Net">
    <img src="images/logo.png" alt="Logo" width="80" height="80">
  </a>

<h3 align="center">Fitz-Net</h3>

  <p align="center">
    A self-hosted platform for Matt's ideas — website, API, IoT devices, and email, all running on Proxmox.
    <br />
    <a href="https://fitznet.org">Live Site</a>
    ·
    <a href="https://github.com/mattlol85/Fitz-Net/issues">Report Bug</a>
    ·
    <a href="https://github.com/mattlol85/Fitz-Net/issues">Request Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#architecture">Architecture</a></li>
    <li>
      <a href="#services">Services</a>
      <ul>
        <li><a href="#fitz-net-website">fitz-net-website</a></li>
        <li><a href="#fitz-net-api">fitz-net-api</a></li>
        <li><a href="#gamerbell">GamerBell</a></li>
        <li><a href="#mail-server">Mail Server</a></li>
      </ul>
    </li>
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

[![Product Name Screen Shot][product-screenshot]](https://fitznet.org)

Fitz-Net is a self-hosted, containerized platform running on a Proxmox home server. It started as a personal website and has grown into a full ecosystem of services — a React frontend, a Spring Boot API, an IoT WebSocket relay for physical button devices, and a self-hosted email server.

Everything runs in Docker Compose on Proxmox. Services are deployed via GitHub Actions to Docker Hub, then pulled on the server.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Architecture

```
Proxmox Home Server
├── Docker Host
│   ├── fitz-net-website    → https://fitznet.org          (React + Nginx)
│   ├── fitz-net-api        → https://api.fitznet.org      (Spring Boot + MongoDB)
│   ├── GamerBell           → https://gamerbell.fitznet.org (Spring Boot WebSocket)
│   └── mail/
│       ├── mailserver      → mail.fitznet.org:25/587/993  (docker-mailserver)
│       └── roundcube       → https://mail.fitznet.org     (Webmail)
└── MongoDB                 → internal only
```

DNS is managed via the registrar. Dynamic DNS (doomdns.org) provides fallback hostnames for services while static `fitznet.org` records serve the primary domains.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Services

### fitz-net-website

**Repo:** [mattlol85/fitz-net-website](https://github.com/mattlol85/fitz-net-website)
**Live:** https://fitznet.org

React 19 frontend served via Nginx in Docker. Features:
- Homepage with animated Fitz-Net branding
- Overwatch 2 tracker — competitive leaderboard, history charts, player avatars
- LiveBoard — real-time collaborative canvas via STOMP WebSocket
- GamerBell widget — live status of physical ESP32 button devices
- Status Dashboard — monitors all service health via Spring Actuator
- User auth (JWT), profile editing, **forgot-password / reset-password flow**

**Stack:** React 19 · Vite 6 · React Router 7 · Vanilla CSS Modules · Docker (Nginx)

---

### fitz-net-api

**Repo:** [mattlol85/fitz-net-api](https://github.com/mattlol85/fitz-net-api)
**Live:** https://api.fitznet.org

Spring Boot 3.4 REST API and WebSocket backend. Features:
- User management (register, login, JWT auth, profile update)
- Overwatch 2 integration via OverFast API (player stats, ratings, history snapshots)
- LiveBoard STOMP WebSocket for shared canvas state
- AES encryption endpoints
- **Password reset via email** — generates secure tokens, sends reset links via `noreply@fitznet.org`

**Stack:** Java 21 · Spring Boot 3.4 · MongoDB · Spring Security (JWT/BCrypt) · Spring Mail · Gradle · Docker

**Key environment variables:**

| Variable | Purpose |
|---|---|
| `JWT_SECRET` | HS256 signing key |
| `MONGO_HOST` / `MONGO_PORT` | MongoDB connection |
| `MAIL_HOST` | SMTP host (`mail.fitznet.org`) |
| `MAIL_USERNAME` | SMTP user (`noreply@fitznet.org`) |
| `MAIL_PASSWORD` | SMTP password |
| `APP_BASE_URL` | Base URL for reset links (`https://fitznet.org`) |

---

### GamerBell

**Repo:** [mattlol85/GamerBell](https://github.com/mattlol85/GamerBell)
**Live:** https://gamerbell.fitznet.org

Spring Boot WebSocket relay service bridging physical ESP32 button devices with the Fitz-Net web UI. Also handles over-the-air (OTA) firmware updates for ESP32s via the GitHub Releases API.

**Stack:** Java 21 · Spring Boot 3.4 · Spring WebSocket · Docker

---

### Mail Server

**Config:** [`Fitz-Net-Agent-Sandbox/mail/`](https://github.com/mattlol85/Fitz-Net-Agent-Sandbox)
**Live:** https://mail.fitznet.org (webmail) · `mail.fitznet.org:993` (IMAP) · `mail.fitznet.org:587` (SMTP)

Self-hosted email for `fitznet.org` running via Docker Compose alongside the other services.

| Container | Image | Role |
|---|---|---|
| `mailserver` | `ghcr.io/docker-mailserver/docker-mailserver` | SMTP (Postfix) + IMAP (Dovecot) + rspamd spam filter + DKIM |
| `roundcube` | `roundcube/roundcubemail` | Browser-based webmail, proxied through Nginx |

**DNS records required:**

| Type | Name | Value |
|---|---|---|
| A | `mail` | `<public IP>` |
| MX | `@` | `mail.fitznet.org` (priority 10) |
| TXT | `@` | `v=spf1 mx ~all` |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:admin@fitznet.org` |
| TXT | `dkim._domainkey` | *(generated by docker-mailserver)* |

See [`mail/SETUP.md`](https://github.com/mattlol85/Fitz-Net-Agent-Sandbox/blob/main/mail/SETUP.md) for the full step-by-step setup guide.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Getting Started

### Prerequisites

- Docker + Docker Compose
- Java 21 (for local development)
- Node 20+ / npm (for frontend development)

### Clone with Submodules

```sh
git clone https://github.com/mattlol85/Fitz-Net.git
cd Fitz-Net
git submodule init
git submodule update
```

### Run API locally

```sh
cd fitz-net-api
./gradlew bootRun
```

### Run Website locally

```sh
cd fitz-net-website
npm install
npm run dev
```

### Start mail stack (on Proxmox Docker host)

```sh
cd mail
docker compose up -d
# First time: create accounts and DKIM
docker exec -ti mailserver setup email add matt@fitznet.org
docker exec -ti mailserver setup email add noreply@fitznet.org
docker exec -ti mailserver setup config dkim
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Roadmap

- [x] React website at fitznet.org
- [x] Spring Boot REST API
- [x] MongoDB user storage with JWT auth
- [x] Overwatch 2 stats tracker
- [x] GamerBell — IoT WebSocket relay + OTA firmware updates
- [x] LiveBoard — real-time collaborative canvas
- [x] Self-hosted email at fitznet.org
- [x] Password reset via email
- [ ] Complete a 1.0 release
- [ ] Hardware client (ESP32 / Raspberry Pi) running additional integrations

See the [open issues](https://github.com/mattlol85/Fitz-Net/issues) for proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



## Contact

Matt - [@mattylol85](https://twitter.com/mattylol85) - mattlol85@gmail.com

Project Link: [https://github.com/mattlol85/Fitz-Net](https://github.com/mattlol85/Fitz-Net)

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/mattlol85/Fitz-Net.svg?style=for-the-badge
[contributors-url]: https://github.com/mattlol85/Fitz-Net/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/mattlol85/Fitz-Net.svg?style=for-the-badge
[forks-url]: https://github.com/mattlol85/Fitz-Net/network/members
[stars-shield]: https://img.shields.io/github/stars/mattlol85/Fitz-Net.svg?style=for-the-badge
[stars-url]: https://github.com/mattlol85/Fitz-Net/stargazers
[issues-shield]: https://img.shields.io/github/issues/mattlol85/Fitz-Net.svg?style=for-the-badge
[issues-url]: https://github.com/mattlol85/Fitz-Net/issues
[license-shield]: https://img.shields.io/github/license/mattlol85/Fitz-Net.svg?style=for-the-badge
[license-url]: https://github.com/mattlol85/Fitz-Net/blob/master/LICENSE.txt
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/mattfitzbk

[product-screenshot]: images/screenshot.png

[node]: https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white
[node-url]: https://nodejs.org/
[React]: https://img.shields.io/badge/React-61DAFB?style=for-the-badge&logo=react&logoColor=black
[React-url]: https://reactjs.org/
[Spring]: https://img.shields.io/badge/Spring-6DB33F?style=for-the-badge&logo=spring&logoColor=white
[Spring-url]: https://spring.io/
[Java]: https://img.shields.io/badge/Java-FFA500?style=for-the-badge&logo=openjdk&logoColor=white
[java-url]: https://www.java.com/
[MongoDB]: https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white
[MongoDB-url]: https://www.mongodb.com/
[Docker]: https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white
[Docker-url]: https://www.docker.com/
