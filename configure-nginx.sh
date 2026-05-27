#!/bin/bash
# ==============================================================================
# NGINX Remote Configurator
# ==============================================================================
set -euo pipefail

# ==========================================
# Argument Validation
# ==========================================
if [ "$#" -ne 3 ]; then
    echo "❌ Error: Missing arguments."
    echo "Usage:   $0 <app_name> <upstream_name> <port>"
    echo "Example: $0 app1 app1_upstream 4060"
    exit 1
fi

# ==========================================
# Configuration Variables
# ==========================================
APP_NAME="$1"
UPSTREAM_NAME="$2"
PORT="$3"

# --- TEMPLATE DIRECTORY CONFIGURATION ---
# Change this to the path where your .conf files are stored
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates" 
# ----------------------------------------

TEMPLATE_CONF="${TEMPLATES_DIR}/app.conf"
TEMPLATE_UPSTREAM="${TEMPLATES_DIR}/upstream.conf"

NGINX_HOST="${NGINX_HOST:-vagrant@192.168.56.10}"
NGINX_CONF_DIR="/etc/nginx/conf.d"

# Safety Check: Templates must exist in the specified directory
if [[ ! -f "$TEMPLATE_CONF" ]] || [[ ! -f "$TEMPLATE_UPSTREAM" ]]; then
    echo "❌ Error: Templates not found in ${TEMPLATES_DIR}"
    echo "Expected: ${TEMPLATE_CONF} and ${TEMPLATE_UPSTREAM}"
    exit 1
fi

# ==========================================
# Phase 1: Generate & Transfer Config Files
# ==========================================
echo "========================================"
echo "📝 Phase 1: Generating Config Files"
echo "========================================"

TEMP_CONF=$(mktemp)
TEMP_UPSTREAM=$(mktemp)
trap 'rm -f "${TEMP_CONF}" "${TEMP_UPSTREAM}"' EXIT

echo "-> Processing templates from: ${TEMPLATES_DIR}"
sed -e "s/\${PORT}/${PORT}/g" \
    -e "s/\${upstream_name}/${UPSTREAM_NAME}/g" \
    -e "s/\${app_name}/${APP_NAME}/g" \
    "${TEMPLATE_CONF}" > "${TEMP_CONF}"

sed -e "s/\${PORT}/${PORT}/g" \
    -e "s/\${upstream_name}/${UPSTREAM_NAME}/g" \
    "${TEMPLATE_UPSTREAM}" > "${TEMP_UPSTREAM}"

echo "-> Transferring to ${NGINX_HOST}..."
scp -q "${TEMP_CONF}" "${NGINX_HOST}:/tmp/${APP_NAME}.conf"
scp -q "${TEMP_UPSTREAM}" "${NGINX_HOST}:/tmp/${APP_NAME}_upstream.conf"

echo "✅ Config files transferred."

# ==========================================
# Phase 2 & 3: Remote Deployment & Verification
# ==========================================
echo ""
echo "========================================"
echo "⚙️  Phase 2 & 3: Applying and Verifying"
echo "========================================"

ssh "${NGINX_HOST}" APP_NAME="$APP_NAME" PORT="$PORT" NGINX_CONF_DIR="$NGINX_CONF_DIR" bash << 'EOF'
    set -euo pipefail

    APP_CONF="${NGINX_CONF_DIR}/${APP_NAME}.conf"
    UPSTREAM_CONF="${NGINX_CONF_DIR}/${APP_NAME}_upstream.conf"
    
    echo "-> Backing up existing configurations (if any)..."
    [ -f "$APP_CONF" ] && sudo cp "$APP_CONF" "${APP_CONF}.bak"
    [ -f "$UPSTREAM_CONF" ] && sudo cp "$UPSTREAM_CONF" "${UPSTREAM_CONF}.bak"

    echo "-> Installing and labeling configurations..."
    sudo install -m 644 -o root -g root "/tmp/${APP_NAME}.conf" "$APP_CONF"
    sudo install -m 644 -o root -g root "/tmp/${APP_NAME}_upstream.conf" "$UPSTREAM_CONF"
    sudo restorecon -v "$APP_CONF" "$UPSTREAM_CONF"

    rm -f "/tmp/${APP_NAME}.conf" "/tmp/${APP_NAME}_upstream.conf"

    echo "-> Testing NGINX configuration..."
    if ! sudo nginx -t; then
        echo "❌ ERROR: NGINX test failed. Conflict detected!"
        echo "-> Initiating Rollback..."
        [ -f "${APP_CONF}.bak" ] && sudo mv "${APP_CONF}.bak" "$APP_CONF" || sudo rm -f "$APP_CONF"
        [ -f "${UPSTREAM_CONF}.bak" ] && sudo mv "${UPSTREAM_CONF}.bak" "$UPSTREAM_CONF" || sudo rm -f "$UPSTREAM_CONF"
        exit 1
    fi

    sudo rm -f "${APP_CONF}.bak" "${UPSTREAM_CONF}.bak"

    echo "-> Adding port ${PORT} to SELinux..."
    if ! sudo semanage port -l | grep -qw "${PORT}"; then
        sudo semanage port -a -t http_port_t -p tcp "${PORT}"
        echo "   Port ${PORT} added to SELinux."
    else
        echo "   Port ${PORT} already allowed."
    fi

    echo "-> Opening port ${PORT} in firewall..."
    sudo firewall-cmd --permanent --add-port=${PORT}/tcp >/dev/null 2>&1
    sudo firewall-cmd --reload >/dev/null 2>&1

    echo "-> Reloading NGINX..."
    sudo systemctl reload nginx

    echo "-> Final Verification: Port Binding..."
    sleep 1
    if ss -tlnp | grep -q ":${PORT}"; then
        echo "✅ SUCCESS: NGINX is listening on port ${PORT}."
    else
        echo "❌ ERROR: Port ${PORT} is not active."
        exit 1
    fi
EOF

echo ""
echo "========================================"
echo "🎉 Configuration Finished Successfully."
echo "========================================"