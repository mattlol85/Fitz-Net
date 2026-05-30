# Mail Server Setup — fitznet.org

Self-hosted email for `fitznet.org` using **docker-mailserver** (Postfix + Dovecot + rspamd + DKIM) and **Roundcube** webmail, running alongside the existing Fitz-Net Docker Compose stack on Proxmox.

---

## Architecture

```
Internet
  │
  ├─ Port 25/465/587  →  mailserver container (Postfix SMTP)
  ├─ Port 993         →  mailserver container (Dovecot IMAPS)
  └─ Port 443         →  Caddy reverse proxy
                              └─ mail.fitznet.org  →  Roundcube (webmail)
```

The mail ports (25, 465, 587, 993) bypass Caddy and forward directly to the `mailserver` container. The webmail UI at `mail.fitznet.org` routes through the existing Caddy reverse proxy like any other service.

---

## Docker Compose

Config lives in `Fitz-Net-Agent-Sandbox/mail/docker-compose.yml`.

```yaml
services:
  mailserver:
    image: ghcr.io/docker-mailserver/docker-mailserver:latest
    hostname: mail.fitznet.org
    ports:
      - "25:25"
      - "465:465"
      - "587:587"
      - "993:993"
    environment:
      - ENABLE_RSPAMD=1
      - ENABLE_CLAMAV=0
      - SSL_TYPE=letsencrypt

  roundcube:
    image: roundcube/roundcubemail:latest
    environment:
      - ROUNDCUBEMAIL_DEFAULT_HOST=ssl://mail.fitznet.org
      - ROUNDCUBEMAIL_SMTP_SERVER=tls://mail.fitznet.org
```

---

## Step-by-Step Setup

### 1. TLS Certificate

```bash
certbot certonly --standalone -d mail.fitznet.org
# Or if Caddy is already running on port 80:
certbot certonly --webroot -w /var/www/html -d mail.fitznet.org
```

### 2. Start the Stack

```bash
cd /opt/mail   # wherever docker-compose.yml lives on the Proxmox host
docker compose up -d
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
# Public key written to ./dms/config/rspamd/dkim/
# Copy the TXT record value into DNS (step 5)
```

### 5. DNS Records

Add at your registrar:

| Type | Name | Value |
|------|------|-------|
| A | `mail` | `<your public IP>` |
| MX | `@` | `mail.fitznet.org` (priority 10) |
| TXT | `@` | `v=spf1 mx ~all` |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:admin@fitznet.org` |
| TXT | `dkim._domainkey` | *(value from step 4)* |

Keep TTL low (300s) if your IP is dynamic — update the `mail` A record if your FiOS IP changes.

### 6. Router Port Forwards

Forward from router's WAN interface to the Docker host's internal IP:

| Port | Protocol | Service |
|------|----------|---------|
| 25 | TCP | SMTP inbound |
| 465 | TCP | SMTPS |
| 587 | TCP | SMTP submission |
| 993 | TCP | IMAPS |
| 80 | TCP | Caddy (already forwarded) |
| 443 | TCP | Caddy (already forwarded) |

### 7. Caddy for Roundcube Webmail

Add to the existing `Caddyfile` on the Docker host:

```
mail.fitznet.org {
    reverse_proxy roundcube:80
}
```

Caddy handles TLS automatically via Let's Encrypt — no manual certificate step needed if you use Caddy for the webmail proxy.

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

The `fitz-net-api` uses `noreply@fitznet.org` to send password reset emails. Set these environment variables on the API container:

```
MAIL_HOST=mail.fitznet.org
MAIL_PORT=587
MAIL_USERNAME=noreply@fitznet.org
MAIL_PASSWORD=<password set in step 3>
APP_BASE_URL=https://fitznet.org
```

The password reset flow:
1. User clicks "Forgot password?" on the login page → `POST /user/forgot-password`
2. API generates a 15-minute UUID token, saves to MongoDB, sends link to `noreply@fitznet.org`
3. User clicks link → `/reset-password?token=...` → sets new password → `POST /user/reset-password`

---

## Reverse DNS (PTR Record)

For best email deliverability, the PTR record for your public IP should resolve to `mail.fitznet.org`. With Verizon FiOS, call support and request a PTR record change for your IP address.

If a PTR record isn't available, configure an SMTP relay (e.g. Brevo free tier) for outbound mail by setting `RELAY_HOST` in `mailcow.conf` or the DMS environment.

---

## Maintenance

```bash
# Pull latest images and restart
docker compose pull && docker compose up -d

# View mail logs
docker logs mailserver

# Backup mail data
tar -czf mail-backup-$(date +%Y%m%d).tar.gz dms/
```

---

## Deliverability Verification

After DNS propagates (up to 48h):

1. Send to [mail-tester.com](https://www.mail-tester.com) — aim for 8+/10
2. Check SPF/DKIM/DMARC at [mxtoolbox.com](https://mxtoolbox.com/SuperTool.aspx)
3. Verify DKIM is signing: `docker exec mailserver setup debug show-mail-logs`
