# Nginx Load Balancer with Keepalived HA Failover

Production-ready Nginx reverse proxy and load balancer with automatic failover using Keepalived (VRRP).

---

## Architecture

```
                    +-----------------------------+
                    |        Floating VIP         |
                    |      192.168.56.200         |
                    +-------------+---------------+
                                  |
             +--------------------+--------------------+
             |                                         |
   +---------+----------+               +-------------+---------+
   |   LB01 (MASTER)    |<--- VRRP --->|   LB02 (BACKUP)       |
   |   192.168.56.101   |   Unicast    |   192.168.56.102      |
   |   Priority: 101    |              |   Priority: 100       |
   +---------+----------+               +-------------+---------+
             |                                         |
             +--------------------+--------------------+
                                  |
                                  v
                    +-------------+-----------------+
                    |       Backend Servers         |
                    |  app1/app2/app3: 192.168.56.10|
                    +-------------------------------+
```

---

## File Structure

```
nginx-configuration/
├── nginx/
│   ├── nginx.conf                        # Main Nginx configuration
│   └── conf.d/
│       ├── app.conf                      # Virtual host (SSL + proxy)
│       ├── cache.conf                    # Proxy micro-cache
│       ├── status.conf                   # Nginx stub_status (metrics endpoint)
│       └── upstream.conf                 # Backend pool
├── templates/
│   ├── app.conf                          # Virtual host template for configure-nginx.sh
│   └── upstream.conf                     # Upstream template for configure-nginx.sh
├── configure-nginx.sh                    # Automated remote deployment script
├── prod-nginx-lb-configuration.txt       # Full production setup guide
└── prod keepalived.conf.txt              # Keepalived VRRP setup guide
```

---

## About the Script

The script configures Nginx for each application. It runs in 3 phases:
1. Renders `templates/app.conf` and `templates/upstream.conf` using `sed`, transfers them to the remote host via `scp`
2. Backs up existing configs, installs new ones, runs `nginx -t` — rolls back automatically on failure
3. Adds the port to SELinux, opens it in the firewall, reloads Nginx, and verifies the port is active

Notes:
- Default target host is `vagrant@192.168.56.10` — override with `NGINX_HOST` env variable
- Templates must exist in the `templates/` directory before running
- Script requires SSH access and `sudo` privileges on the remote host
- SELinux and firewalld steps are RHEL-specific — adjust for Debian-based systems

```bash
./configure-nginx.sh <app_name> <upstream_name> <port>

# Example
./configure-nginx.sh app1 app1_upstream 8081

# Override target host
NGINX_HOST=vagrant@192.168.56.101 ./configure-nginx.sh app1 app1_upstream 8081
```

---

## Quick Reference

```bash
sudo nginx -t && sudo systemctl reload nginx   # Test and reload
sudo systemctl status keepalived               # Keepalived status
ip addr show                                   # Verify VIP is active
sudo sysctl -p                                 # Apply kernel parameters
curl http://127.0.0.1:8080/nginx_status        # Nginx metrics
```

---

## Notes
- Replace `auth_pass` in `keepalived.conf` before deploying
- Place SSL certificates at `/etc/nginx/ssl/` before starting Nginx
- Set cache dir ownership: `nginx:nginx` (RHEL) or `www-data:www-data` (Debian)
- The script is developed for RHEL-based Linux. For Debian-based systems, replace `firewalld` with `ufw` and `SELinux` with `AppArmor` or remove it.
- Nginx configuration syntax requires Nginx 1.26+. If you are running an older version, some directives (e.g., `http2 on`) may need to be adjusted
