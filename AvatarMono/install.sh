#!/bin/bash
#
# install.sh — downloads, installs, and starts the application as a
# systemd service.
#
# Usage: sudo ./install.sh

set -e


VENDOR="PriceEasy"
APP_NAME="AvatarMono"          # Used for the /opt folder name
SERVICE_NAME="AvatarMono"           # Used for the systemd service name
EXE_NAME="AvatarMono.exe"           # Must match your .exe filename exactly
DLL_NAME="YourApp.dll"

# Direct-download URL for the app package (must resolve straight to the
# file, not a OneDrive viewer page — see notes from earlier).
DOWNLOAD_URL="https://francis-r.github.io/Avatar/AvatarMono/avatar-mono.zip"
ARCHIVE_NAME="avatar-mono.zip"
# ===============================================================

INSTALL_DIR="/opt/${VENDOR}/${APP_NAME}"
TMP_DIR="$(mktemp -d)"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ---------------------------------------------------------------
# 0. Must run as root (needed for /opt, package install, systemd)
# ---------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "Please run this installer with sudo: sudo ./install.sh"
    exit 1
fi

# The systemd service should run as a normal user, not root, even
# though the installer itself needs root. Use the account that
# invoked sudo; fall back with a warning if run directly as root.
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    APP_USER="$SUDO_USER"
else
    echo "WARNING: Could not determine a non-root invoking user."
    echo "         The service will be configured to run as root,"
    echo "         which is not recommended."
    APP_USER="root"
fi

# ---------------------------------------------------------------
# 1. Check for Mono, offer to install it if missing
# ---------------------------------------------------------------
install_mono() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y mono-complete
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y mono-complete
    elif command -v yum >/dev/null 2>&1; then
        yum install -y mono-complete
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm mono
    else
        echo "ERROR: Could not detect a supported package manager (apt/dnf/yum/pacman)."
        echo "       Please install Mono manually: https://www.mono-project.com/download/stable/"
        exit 1
    fi
}

if command -v mono >/dev/null 2>&1; then
    echo "=== Mono is already installed: $(mono --version | head -n1)"
else
    echo "=== Mono was not found on this system."
    read -r -p "Install Mono now? [y/N]: " CONFIRM
    case "$CONFIRM" in
        [Yy]*)
            echo "=== Installing Mono..."
            install_mono
            ;;
        *)
            echo "Mono is required to run ${EXE_NAME}. Exiting."
            exit 1
            ;;
    esac
fi

# ---------------------------------------------------------------
# 2. Download and extract the application package
# ---------------------------------------------------------------
command -v curl >/dev/null 2>&1 || { echo "curl is required but not installed."; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "unzip is required but not installed."; exit 1; }

echo "=== Downloading application package..."
curl -L -f -o "${TMP_DIR}/${ARCHIVE_NAME}" "${DOWNLOAD_URL}"

echo "=== Extracting..."
unzip -o -q "${TMP_DIR}/${ARCHIVE_NAME}" -d "${TMP_DIR}/extracted"

# If the zip contains a single top-level folder, drill into it;
# otherwise use the extraction root as-is.
SRC_DIR="${TMP_DIR}/extracted"
if [ "$(find "${SRC_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ] && \
   [ "$(find "${SRC_DIR}" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 0 ]; then
    SRC_DIR="$(find "${SRC_DIR}" -mindepth 1 -maxdepth 1 -type d)"
fi

# ---------------------------------------------------------------
# 3. Copy files into /opt
# ---------------------------------------------------------------
echo "=== Installing ${APP_NAME} to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"

cp "${SRC_DIR}/${EXE_NAME}" "${INSTALL_DIR}/"
cp "${SRC_DIR}/${DLL_NAME}" "${INSTALL_DIR}/"
# Optional: copy any other files, e.g. config, icons
# cp "${SRC_DIR}/config.json" "${INSTALL_DIR}/"

chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}" 2>/dev/null || true

rm -rf "${TMP_DIR}"

EXE_PATH="${INSTALL_DIR}/${EXE_NAME}"

if [ ! -f "$EXE_PATH" ]; then
    echo "ERROR: Expected file not found after extraction: $EXE_PATH"
    exit 1
fi

echo "=== Using service user:  $APP_USER"
echo "=== App folder:          $INSTALL_DIR"

# ---------------------------------------------------------------
# 4. Create and start the systemd service (formerly setup.sh)
# ---------------------------------------------------------------
echo "=== Creating service file ==="
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=$SERVICE_NAME (Mono console app)
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/mono "$EXE_PATH"
Restart=always
RestartSec=5

# Prevent restart storm if app crashes repeatedly
StartLimitIntervalSec=60
StartLimitBurst=10

# Only kill the main mono process
KillMode=process
KillSignal=SIGINT

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "=== Activating service ==="
systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service"
systemctl restart "$SERVICE_NAME.service"

echo ""
echo "=== DONE ==="
echo "${APP_NAME} installed at $INSTALL_DIR"
echo "Service '$SERVICE_NAME' created and started, running as user '$APP_USER'."
echo ""

systemctl status "$SERVICE_NAME.service" --no-pager -l

echo ""
echo "Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo systemctl restart $SERVICE_NAME"
echo "  journalctl -u $SERVICE_NAME -f          # live logs"
echo "  sudo systemctl stop $SERVICE_NAME       # stop (but will restart unless masked)"
echo ""
echo "To stop temporarily for update:"
echo "  sudo systemctl stop $SERVICE_NAME"
echo "  sudo systemctl mask $SERVICE_NAME       # prevents restart & boot start"
echo "  # ... do your update / replace files ..."
echo "  sudo systemctl unmask $SERVICE_NAME"
echo "  sudo systemctl start $SERVICE_NAME"
