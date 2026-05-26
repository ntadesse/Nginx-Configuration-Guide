# Nginx Load Balancer with Keepalived HA Failover

Production-ready configuration for a high-availability Nginx reverse proxy and load balancer with automatic failover using Keepalived (VRRP). Includes security hardening, SSL termination, micro-caching, and an automated deployment script.

---

## Architecture

```
                        ┌─────────────────────────────┐
                        │   Floating VIP               │
                        │   192.168.56.200             │
                        └────────────┬────────────────┘
                                     │
               ┌─────────────────────┴──────────────────────┐
               │                                            │
     ┌─────────▼──────────┐                    ┌───────────▼────────────┐
     │  LB01 (MASTER)     │◄──── VRRP ────────►│  LB02 (BACKUP)         │
     │  192.168.56.101    │    Unicast          │  192.168.56.102        │
     │  Priority: 101     │                    │  Priority: 100         │
     └─────────┬──────────┘                    └────────────────────────┘
               │
     ┌─────────┴──────────────────────────┐
     │         Backend Servers            │
     │  app1: 192.168.56.10:PORT          │
     │  app2: 192.168.56.10:PORT          │
     │  app3: 192.168.56.10:PORT          │
     └────────────────────────────────────┘
```

- Two load balancer nodes share a floating VIP (`192.168.56.200`)
- Keepalived promotes the backup node automatically if the master fails
- Nginx health is monitored every 3 seconds via a script; failure triggers failover

---

## File Structure

```
nginx-configuration/
├── nginx/
│   ├── nginx.conf                        # Main Nginx configuration
│   └── conf.d/
│       ├── app.conf                      # Virtual host template (SSL + proxy)
│       ├── cache.conf                    # Proxy micro-cache configuration
│       └── upstream.conf                 # Upstream backend template
├── configure-nginx.sh                    # Automated remote deployment script
├── prod-nginx-lb-configuration.txt       # Full production setup guide
└── prod keepalived.conf.txt              # Keepalived VRRP setup guide
```

---

## Configuration Files

### `nginx.conf` — Main Configuration
- Runs as `www-data`, auto-scales worker processes
- Gzip compression enabled for `text/plain`, `text/css`, `application/json`, `application/javascript`
- `server_tokens off` — hides Nginx version from responses
- Includes all configs from `/etc/nginx/conf.d/*.conf`

### `upstream.conf` — Backend Pool Template
- Consistent hash load balancing (`hash $remote_addr consistent`) for session stickiness
- Each backend has `max_fails=3 fail_timeout=5s` for automatic health-based removal
- `keepalive 32` — maintains 32 persistent connections to backends

### `app.conf` — Virtual Host Template
SSL/TLS hardening:
- TLSv1.2 and TLSv1.3 only
- Strong cipher suite: `ECDHE-ECDSA-AES256-GCM-SHA384`, `CHACHA20-POLY1305`
- HSTS, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection headers

Proxy settings:
- HTTP/1.1 with keepalive to backends
- Configurable connect timeout (3s) and read timeout (60s)
- Automatic failover on `error`, `timeout`, `5xx` responses via `proxy_next_upstream`
- Micro-cache enabled with session-based bypass (`proxy_cache_bypass $cookie_session`)

### `cache.conf` — Micro-Cache
- Cache path: `/var/cache/nginx/microcache`
- Zone: `microcache` with 50MB key store, 2GB max size, 60min inactive expiry
- `proxy_cache_lock on` — prevents cache stampede on cache miss

### `configure-nginx.sh` — Automated Deployment Script
Deploys Nginx virtual host configs to a remote server over SSH in 3 phases:

| Phase | Action |
|-------|--------|
| 1 | Renders templates with `sed`, transfers via `scp` |
| 2 | Backs up existing configs, installs new ones, runs `nginx -t` |
| 3 | Adds SELinux port label, opens firewall port, reloads Nginx, verifies port binding |

Rolls back automatically if `nginx -t` fails.

**Usage:**
```bash
./configure-nginx.sh <app_name> <upstream_name> <port>

# Example
./configure-nginx.sh app1 app1_upstream 4060
```

Set `NGINX_HOST` environment variable to override the default target (`vagrant@192.168.56.10`):
```bash
NGINX_HOST=user@192.168.56.101 ./configure-nginx.sh app1 app1_upstream 4060
```

---

## Keepalived Setup Summary

- VRRP instance `VI_SITE` with `virtual_router_id 51`
- Unicast mode between `192.168.56.101` (MASTER) and `192.168.56.102` (BACKUP)
- Nginx health check script at `/usr/local/libexec/keepalived/chk_nginx.sh`
  - Checks every 3 seconds, fails after 3 consecutive failures, recovers after 2 successes
  - Adjusts VRRP priority by ±50 on state change
- IPTables rules restrict VRRP traffic to `192.168.56.0/24`
- Kernel parameters tuned: `ip_forward`, `arp_ignore`, `arp_announce`

---

## Log Rotation

Configured via `/etc/logrotate.d/nginx`:
- Daily rotation, 30-day retention
- Forced rotation if any log exceeds 100MB
- Compressed with `gzip`, date-stamped filenames (e.g., `app01_access.log-20240101.gz`)
- Zero-downtime reload using `kill -USR1` on Nginx PID

---

## Quick Reference

```bash
# Test and reload Nginx
sudo nginx -t && sudo systemctl reload nginx

# Check Keepalived status
sudo systemctl status keepalived

# Apply kernel parameters
sudo sysctl -p

# Verify VIP is active
ip addr show enp0s8
```

---

## Security Notes

- Replace `auth_pass` in `keepalived.conf` with a strong secret before deploying
- Replace placeholder IPs with your actual network addresses
- SSL certificates must be placed at `/etc/nginx/ssl/` before starting Nginx
- For Debian-based systems: `chown www-data:www-data /var/cache/nginx/microcache`
- For RHEL-based systems: `chown nginx:nginx /var/cache/nginx/microcache`
