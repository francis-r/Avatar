#!/bin/bash
#
# uninstall.sh — reverses what install.sh set up: stops and removes
# the systemd service, deletes the unit file, removes the install
# directory.
#
# Usage: sudo ./uninstall.sh

set -e

# ================== MUST MATCH install.sh ==================
VENDOR="PriceEasy"
APP_NAME="AvatarMono"
SERVICE_NAME="AvatarMono"
# ==============================================================

INSTALL_DIR="/opt/${VENDOR}/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo ./uninstall.sh"
    exit 1
fi

echo "=== Stopping and disabling ${SERVICE_NAME} service..."
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

if [ -f "$SERVICE_FILE" ]; then
    echo "=== Removing service file..."
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
fi

if [ -d "$INSTALL_DIR" ]; then
    echo "=== Removing ${INSTALL_DIR}..."
    rm -rf "$INSTALL_DIR"
fi

# Only remove the parent vendor folder if it's now empty
rmdir "/opt/${VENDOR}" 2>/dev/null || true

echo ""
echo "=== DONE. ${APP_NAME} has been uninstalled."
echo "Note: Mono itself was not removed, since other software may depend on it."
echo "To remove Mono too (only if nothing else needs it):"
echo "  sudo apt-get remove --purge mono-complete   # Debian/Ubuntu"
