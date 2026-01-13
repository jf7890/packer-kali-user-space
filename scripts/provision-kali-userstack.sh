#!/usr/bin/env bash
set -euo pipefail

# This script is intended to run as root (systemd first-boot).
# Comments are English-only by request.

export DEBIAN_FRONTEND=noninteractive

# Re-run as root if needed (e.g., SSH user is "kali")
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -n -E bash "$0" "$@"
fi

PROVISION_MARKER="/var/lib/capstone-userstack/provisioned"
if [[ -f "$PROVISION_MARKER" ]]; then
  echo "[SKIP] Capstone provisioning already completed."
  exit 0
fi

USERSTACK_SRC="/opt/capstone-userstack-src"
USERSTACK_DST="/opt/capstone-userstack"
WAZUH_MANAGER="${WAZUH_MANAGER:-172.16.99.11}"

echo "[1/10] Configure apt sources"
cat > /etc/apt/sources.list <<'EOF'
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
# deb-src http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
EOF

echo "[2/10] Apt update + base packages"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release jq unzip \
  qemu-guest-agent \
  docker.io \
  cloud-init \
  tigervnc-standalone-server dbus-x11

# Optional tools (best-effort)
apt-get install -y --no-install-recommends docker-compose-plugin || true
apt-get install -y --no-install-recommends kali-tools-web || true

COMPOSE_BIN=""
COMPOSE_ARGS=""
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN="/usr/bin/docker"
    COMPOSE_ARGS="compose"
  fi
fi
if [[ -z "$COMPOSE_BIN" ]] && command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_BIN="/usr/bin/docker-compose"
fi
if [[ -z "$COMPOSE_BIN" ]] && apt-cache show docker-compose >/dev/null 2>&1; then
  if apt-get install -y docker-compose; then
    COMPOSE_BIN="/usr/bin/docker-compose"
  fi
fi
if [[ -z "$COMPOSE_BIN" ]]; then
  echo "ERROR: No docker compose package available in apt repos." >&2
  exit 1
fi

if [[ -n "$COMPOSE_ARGS" ]]; then
  COMPOSE_CMD=("$COMPOSE_BIN" "$COMPOSE_ARGS")
else
  COMPOSE_CMD=("$COMPOSE_BIN")
fi

SYSTEMD_COMPOSE_CMD="${COMPOSE_CMD[*]}"
SYSTEMD_COMPOSE_START="${SYSTEMD_COMPOSE_CMD} up -d"
SYSTEMD_COMPOSE_STOP="${SYSTEMD_COMPOSE_CMD} down"

echo "[3/10] Enable core services"
systemctl enable --now qemu-guest-agent > /dev/null 2>&1 || true
systemctl enable --now docker > /dev/null 2>&1 || true
systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service > /dev/null 2>&1 || true
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init clean --logs > /dev/null 2>&1 || true
  cloud-init init > /dev/null 2>&1 || true
  cloud-init modules --mode=config > /dev/null 2>&1 || true
  cloud-init modules --mode=final > /dev/null 2>&1 || true
fi

# Allow 'kali' user to run docker without sudo (if the user exists)
if id kali >/dev/null 2>&1; then
  usermod -aG docker kali || true
fi

echo "[4/10] Configure VNC (XFCE)"
if command -v vncserver >/dev/null 2>&1; then
  mkdir -p /home/kali/.vnc
  chown kali:kali /home/kali/.vnc
  chmod 700 /home/kali/.vnc

  cat > /home/kali/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export SHELL=/bin/bash
startxfce4 &
EOF
  chmod 755 /home/kali/.vnc/xstartup
  chown kali:kali /home/kali/.vnc/xstartup

  su - kali -c "printf \"kali1234\n\" | vncpasswd -f > ~/.vnc/passwd"
  chmod 600 /home/kali/.vnc/passwd
  chown kali:kali /home/kali/.vnc/passwd

  cat > /etc/systemd/system/vncserver@.service <<'EOF'
[Unit]
Description=TigerVNC Server on display :%i
After=network.target

[Service]
Type=forking
User=kali
PAMName=login
PIDFile=/home/kali/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :%i -geometry 1280x800 -depth 24 -localhost no
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload > /dev/null 2>&1 || true
  systemctl enable vncserver@1.service > /dev/null 2>&1 || true
fi

echo "[5/10] Install Wazuh agent (optional; does not start until manager is set)"
# Wazuh provides a Debian/Ubuntu repo that also works for Kali (Debian-based).
# If external downloads are blocked, the install is skipped.
if ! dpkg -s wazuh-agent >/dev/null 2>&1; then
  if curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update -y \
    && apt-get install -y wazuh-agent; then
    echo "Wazuh agent installed."
  else
    echo "Wazuh install failed; continuing without it." >&2
  fi
fi

# Keep the agent disabled by default; the manager address will be configured later.
WAZUH_CONF="/var/ossec/etc/ossec.conf"
if [[ -f "$WAZUH_CONF" ]]; then
  # Set a deterministic placeholder address
  sed -i 's|<address>[^<]*</address>|<address>__WAZUH_MANAGER__</address>|' "$WAZUH_CONF" || true

  # Add logcollector entries only once
  if ! grep -q "CAPSTONE_USERSTACK_LOGS" "$WAZUH_CONF"; then
    # Insert before closing tag (skip if perl is unavailable)
    if command -v perl >/dev/null 2>&1; then
      perl -0777 -i -pe 's#</ossec_config>#  <!-- CAPSTONE_USERSTACK_LOGS -->\n  <localfile>\n    <log_format>syslog</log_format>\n    <location>/opt/capstone-userstack/logs/nginx/access.log</location>\n  </localfile>\n  <localfile>\n    <log_format>syslog</log_format>\n    <location>/opt/capstone-userstack/logs/nginx/error.log</location>\n  </localfile>\n  <localfile>\n    <log_format>json</log_format>\n    <location>/opt/capstone-userstack/logs/modsecurity/modsec_audit.log</location>\n  </localfile>\n  <localfile>\n    <log_format>syslog</log_format>\n    <location>/opt/capstone-userstack/logs/apache/access.log</location>\n  </localfile>\n  <localfile>\n    <log_format>syslog</log_format>\n    <location>/opt/capstone-userstack/logs/apache/error.log</location>\n  </localfile>\n  <localfile>\n    <log_format>syslog</log_format>\n    <location>/opt/capstone-userstack/logs/mysql/error.log</location>\n  </localfile>\n  <localfile>\n    <log_format>syslog</log_format>\n    <location>/opt/capstone-userstack/logs/postgres/postgresql.log</location>\n  </localfile>\n</ossec_config>#s' "$WAZUH_CONF" || true
    else
      echo "perl not available; skipping Wazuh logcollector insertion." >&2
    fi
  fi
fi

systemctl stop wazuh-agent > /dev/null 2>&1 || true
systemctl disable wazuh-agent > /dev/null 2>&1 || true

echo "[6/10] Helper: set Wazuh manager address later"
cat > /usr/local/bin/wazuh-set-manager <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: wazuh-set-manager <MANAGER_IP_OR_HOSTNAME>" >&2
  exit 1
fi
mgr="$1"
conf="/var/ossec/etc/ossec.conf"
if [[ ! -f "$conf" ]]; then
  echo "Cannot find $conf" >&2
  exit 1
fi

# Replace the placeholder with the provided manager address
sed -i "s|<address>__WAZUH_MANAGER__</address>|<address>${mgr}</address>|" "$conf" || true

# Enable and start the agent without blocking the current SSH session
systemctl enable wazuh-agent > /dev/null 2>&1 || true
systemctl start --no-block wazuh-agent > /dev/null 2>&1 || true
systemctl restart wazuh-agent > /dev/null 2>&1 || true

# Best-effort status output without a pager
systemctl status wazuh-agent --no-pager > /dev/null 2>&1 || true
EOF
chmod +x /usr/local/bin/wazuh-set-manager

if [[ -n "$WAZUH_MANAGER" ]]; then
  cat > /etc/systemd/system/capstone-wazuh-manager.service <<EOF
[Unit]
Description=Configure Wazuh agent manager
Wants=network-online.target
After=network-online.target
ConditionPathExists=/var/ossec/etc/ossec.conf

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wazuh-set-manager ${WAZUH_MANAGER}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload > /dev/null 2>&1 || true
  systemctl enable capstone-wazuh-manager.service > /dev/null 2>&1 || true
  /usr/local/bin/wazuh-set-manager "${WAZUH_MANAGER}" || true
fi

echo "[7/10] Install capstone userstack files"
rm -rf "$USERSTACK_DST"
mkdir -p "$USERSTACK_DST"
if compgen -G "$USERSTACK_SRC/*" >/dev/null; then
  cp -a "$USERSTACK_SRC"/* "$USERSTACK_DST"/
else
  echo "WARNING: No userstack files found in $USERSTACK_SRC" >&2
fi

# Ensure log directories exist
mkdir -p \
  "$USERSTACK_DST/logs/nginx" \
  "$USERSTACK_DST/logs/modsecurity" \
  "$USERSTACK_DST/logs/apache" \
  "$USERSTACK_DST/logs/mysql" \
  "$USERSTACK_DST/logs/postgres" \
  "$USERSTACK_DST/logs/juiceshop"

# Create .env from template if missing
if [[ -f "$USERSTACK_DST/.env.example" && ! -f "$USERSTACK_DST/.env" ]]; then
  cp "$USERSTACK_DST/.env.example" "$USERSTACK_DST/.env"
fi

chmod +x "$USERSTACK_DST/scripts"/*.sh 2>/dev/null || true

echo "[8/10] Create systemd service: capstone-userstack"
cat > /etc/systemd/system/capstone-userstack.service <<EOF
[Unit]
Description=Capstone user lab stack (DVWA + JuiceShop + nginx-love)
Wants=network-online.target docker.service
After=network-online.target docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/capstone-userstack
ExecStart=${SYSTEMD_COMPOSE_START}
ExecStop=${SYSTEMD_COMPOSE_STOP}
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload > /dev/null 2>&1 || true
systemctl enable capstone-userstack.service > /dev/null 2>&1 || true

echo "[9/10] Pre-pull/build docker images (best-effort)"
# Avoid failing the whole provisioning if a registry is down.
(
  cd "$USERSTACK_DST"
  "${COMPOSE_CMD[@]}" pull || true
  "${COMPOSE_CMD[@]}" build --pull || true
) || true

systemctl start --no-block capstone-userstack.service > /dev/null 2>&1 || true

echo "[10/10] Finalize"
apt-get autoremove -y > /dev/null 2>&1 || true
apt-get clean > /dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true
mkdir -p "$(dirname "$PROVISION_MARKER")"
touch "$PROVISION_MARKER"
systemctl disable capstone-firstboot.service > /dev/null 2>&1 || true

echo "DONE: userstack provisioned (docker + wazuh + nginx-love)."
