# Mail Server Setup — fitznet.org

Self-hosted email for `fitznet.org` using **docker-mailserver** (Postfix + Dovecot + rspamd + DKIM) and **Roundcube** webmail, running alongside the existing Fitz-Net Docker Compose stack on Proxmox.

---

## Architecture

```
Internet
  │
  ├─ Port 25/465/587  →  Home Router  →  mailserver container (Postfix SMTP)
  ├─ Port 993         →  Home Router  →  mailserver container (Dovecot IMAPS)
  └─ Port 80/443      →  Home Router  →  Caddy
                                              └─ mail.fitznet.org  →  Roundcube (webmail)
```

Mail ports (25, 465, 587, 993) are port-forwarded from the router directly to the `mailserver` container, bypassing Caddy. The webmail UI at `mail.fitznet.org` routes through Caddy like every other service — Caddy provisions and renews the TLS cert automatically.

---

## Docker Compose

Config lives in `Fitz-Net-Agent-Sandbox/mail/docker-compose.yml`. Roundcube joins the `fitznet` external network so `caddy-docker-proxy` can route to it via label.

```yaml
services:
  mailserver:
    image: ghcr.io/docker-mailserver/docker-mailserver:latest
    container_name: mailserver
    hostname: mail.fitznet.org
    ports:
      - "25:25"
      - "465:465"
      - "587:587"
      - "993:993"
    volumes:
      - ./dms/mail-data/:/var/mail/
      - ./dms/mail-state/:/var/mail-state/
      - ./dms/mail-logs/:/var/log/mail/
      - ./dms/config/:/tmp/docker-mailserver/
      - caddy_data:/caddy-certs:ro        # share Caddy's auto-provisioned certs
    environment:
      - ENABLE_RSPAMD=1
      - ENABLE_CLAMAV=0
      - ENABLE_FAIL2BAN=1
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/caddy-certs/certificates/acme-v02.api.letsencrypt.org-directory/mail.fitznet.org/mail.fitznet.org.crt
      - SSL_KEY_PATH=/caddy-certs/certificates/acme-v02.api.letsencrypt.org-directory/mail.fitznet.org/mail.fitznet.org.key
    cap_add:
      - NET_ADMIN
      - SYS_PTRACE
    restart: unless-stopped

  roundcube:
    image: roundcube/roundcubemail:latest
    container_name: roundcube
    environment:
      - ROUNDCUBEMAIL_DEFAULT_HOST=ssl://mail.fitznet.org
      - ROUNDCUBEMAIL_DEFAULT_PORT=993
      - ROUNDCUBEMAIL_SMTP_SERVER=tls://mail.fitznet.org
      - ROUNDCUBEMAIL_SMTP_PORT=587
      - ROUNDCUBEMAIL_DB_TYPE=sqlite
    volumes:
      - roundcube-data:/var/roundcube/db
    expose:
      - "80"
    labels:
      caddy: mail.fitznet.org
      caddy.reverse_proxy: "{{upstreams 80}}"
      caddy_network: fitznet
    networks:
      - fitznet
    restart: unless-stopped

volumes:
  roundcube-data:
  caddy_data:                             # external volume owned by the main fitznet stack
    external: true

networks:
  fitznet:
    external: true
```

**How TLS works:** Caddy auto-provisions a Let's Encrypt cert for `mail.fitznet.org` when it first proxies a request to Roundcube. The mailserver container mounts the same `caddy_data` volume read-only and reads the cert directly — no certbot step needed.

> **First-boot ordering:** Start the fitznet stack first so Caddy has time to provision the cert before the mailserver reads it. If the mailserver starts before the cert exists, restart it after Caddy has provisioned: `docker restart mailserver`.

---

## Step-by-Step Setup

### 1. Ensure the fitznet external network exists

```bash
docker network create fitznet   # skip if already done for the main stack
```

### 2. Start the Stack

```bash
cd ~/fitznet-mail   # wherever docker-compose.yml lives on the host
docker compose up -d

# Caddy will provision the mail.fitznet.org cert on first request.
# Once the cert exists (~30s), restart mailserver so it picks it up:
docker restart mailserver
```

### 3. Create Mailboxes

```bash
docker exec -ti mailserver setup email add matt@fitznet.org
docker exec -ti mailserver setup email add noreply@fitznet.org
docker exec -ti mailserver setup email add admin@fitznet.org
```

### 4. Generate DKIM Keys

```bash
docker exec -ti mailserver setup config dkim
# Public key written to ./dms/config/rspamd/dkim/fitznet.org.txt
# Open that file — copy the TXT record value into your DNS provider (step 5)
```

### 5. DNS Records

Add at your domain registrar:

| Type | Name | Value |
|------|------|-------|
| A | `mail` | `<your public IP>` |
| MX | `@` | `mail.fitznet.org` (priority 10) |
| TXT | `@` | `v=spf1 mx ~all` |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:admin@fitznet.org` |
| TXT | `dkim._domainkey` | *(value from step 4)* |

> If your FiOS IP is dynamic, keep TTL at 300s and update the `mail` A record whenever it changes.

### 6. Router Port Forwards

Forward from the router's WAN interface to the Docker host's internal IP:

| Port | Protocol | Destination |
|------|----------|-------------|
| 25 | TCP | Docker host (mailserver) |
| 465 | TCP | Docker host (mailserver) |
| 587 | TCP | Docker host (mailserver) |
| 993 | TCP | Docker host (mailserver) |
| 80 | TCP | Docker host (Caddy) — already forwarded |
| 443 | TCP | Docker host (Caddy) — already forwarded |

---

## Connecting Email Clients

Use these settings in Thunderbird, Apple Mail, iOS Mail, etc.:

| Setting | Value |
|---------|-------|
| IMAP server | `mail.fitznet.org` |
| IMAP port | `993` (SSL/TLS) |
| SMTP server | `mail.fitznet.org` |
| SMTP port | `587` (STARTTLS) |
| Username | Full address, e.g. `matt@fitznet.org` |

---

## Fitz-Net API Integration

The `fitz-net-api` sends password reset emails from `noreply@fitznet.org`. Add these to the API container's environment (in the main `fitznet/docker-compose.yml` or `.env`):

```env
MAIL_HOST=mail.fitznet.org
MAIL_PORT=587
MAIL_USERNAME=noreply@fitznet.org
MAIL_PASSWORD=<password set in step 3>
APP_BASE_URL=https://fitznet.org
```

The password reset flow:
1. User clicks "Forgot password?" → `POST /user/forgot-password`
2. API generates a 15-minute UUID token, saves to MongoDB, emails a reset link via `noreply@fitznet.org`
3. User clicks link → `/reset-password?token=...` → sets new password → logs in

---

## Reverse DNS (PTR Record)

For best deliverability, the PTR record for your public IP should resolve to `mail.fitznet.org`. Call Verizon FiOS support and ask them to set a reverse DNS entry for your static/dynamic IP. This is one of the strongest signals to receiving mail servers that you're legitimate.

---

## Maintenance

```bash
# Update images
docker compose pull && docker compose up -d

# View mail logs
docker logs mailserver

# Backup all mail data
tar -czf mail-backup-$(date +%Y%m%d).tar.gz dms/
```

---

## Deliverability Verification

After DNS propagates (up to 48h):

1. Send a test to [mail-tester.com](https://www.mail-tester.com) — aim for 8+/10
2. Check SPF/DKIM/DMARC at [mxtoolbox.com](https://mxtoolbox.com/SuperTool.aspx)
3. Confirm DKIM is signing outbound: `docker exec mailserver setup debug show-mail-logs`
