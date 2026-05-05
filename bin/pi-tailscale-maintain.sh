#!/usr/bin/env bash
set -euo pipefail

ROLE_DIR="/root/pi-tailscale-role"
ENV_FILE="$ROLE_DIR/.env"
ENV_EXAMPLE="$ROLE_DIR/.env.example"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./install.sh" >&2
  exit 1
fi

if [[ "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" != "$ROLE_DIR" ]]; then
  echo "This role expects to live at:" >&2
  echo "  $ROLE_DIR" >&2
  echo >&2
  echo "Move or clone the repo there, then rerun:" >&2
  echo "  cd /root" >&2
  echo "  git clone https://github.com/windweaver828/pi-tailscale-role.git" >&2
  echo "  cd /root/pi-tailscale-role" >&2
  echo "  sudo ./install.sh" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer currently supports Debian/Raspberry Pi OS systems with apt-get." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_EXAMPLE" ]]; then
    echo "Missing env example file: $ENV_EXAMPLE" >&2
    exit 1
  fi

  cp "$ENV_EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  echo "Created:"
  echo "  $ENV_FILE"
  echo
  echo "Edit it, then rerun:"
  echo "  sudo nano $ENV_FILE"
  echo "  sudo ./install.sh"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

PI_TS_HOSTNAME="${PI_TS_HOSTNAME:-$(hostname)}"
PI_TS_AUTH_KEY="${PI_TS_AUTH_KEY:-}"
PI_TS_EXTRA_UP_ARGS="${PI_TS_EXTRA_UP_ARGS:-}"
PI_TS_ACCEPT_DNS="${PI_TS_ACCEPT_DNS:-false}"
PI_TS_ACCEPT_ROUTES="${PI_TS_ACCEPT_ROUTES:-false}"

install_tailscale_if_needed() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale already installed"
    return 0
  fi

  echo "Tailscale not found; installing from official Tailscale repository"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://tailscale.com/install.sh | sh
  else
    echo "Neither curl nor wget is installed; installing curl first"
    apt-get install -y curl
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
}

tailscale_is_authenticated() {
  command -v tailscale >/dev/null 2>&1 || return 1
  tailscale ip -4 >/dev/null 2>&1
}

run_tailscale_up() {
  local auth_key="${1:-}"

  local args=(
    up
    "--hostname=${PI_TS_HOSTNAME}"
    "--accept-dns=${PI_TS_ACCEPT_DNS}"
    "--accept-routes=${PI_TS_ACCEPT_ROUTES}"
  )

  if [[ -n "$auth_key" ]]; then
    args+=("--auth-key=${auth_key}")
  fi

  if [[ -n "${PI_TS_EXTRA_UP_ARGS:-}" ]]; then
    # Intended for simple extra flags like: --ssh
    # shellcheck disable=SC2206
    local extra_args=($PI_TS_EXTRA_UP_ARGS)
    args+=("${extra_args[@]}")
  fi

  tailscale "${args[@]}"
}

authenticate_tailscale_if_needed() {
  echo "Checking Tailscale authentication state"

  if tailscale_is_authenticated; then
    echo "Tailscale already authenticated"
    return 0
  fi

  if [[ -n "${PI_TS_AUTH_KEY:-}" ]]; then
    echo "Tailscale not authenticated; using configured auth key"
    run_tailscale_up "$PI_TS_AUTH_KEY"
    echo "Tailscale authenticated with configured auth key"
    return 0
  fi

  echo
  echo "Tailscale is installed but not authenticated."
  echo
  echo "Choose an auth method:"
  echo "  1) Paste a Tailscale auth key now"
  echo "  2) Start normal Tailscale browser/device auth, then press Enter after finished"
  echo "  3) Skip auth for now and finish installing"
  echo

  local choice
  read -r -p "Choice [1/2/3]: " choice

  case "$choice" in
  1)
    local entered_key
    read -r -s -p "Paste Tailscale auth key: " entered_key
    echo

    if [[ -z "$entered_key" ]]; then
      echo "No auth key entered; skipping auth"
      return 1
    fi

    echo "Authenticating with provided auth key"
    run_tailscale_up "$entered_key"
    echo "Tailscale authenticated with provided auth key"
    return 0
    ;;

  2)
    echo
    echo "Starting normal Tailscale auth."
    echo "Open the auth URL shown below, finish login/approval, then come back here."
    echo

    run_tailscale_up "" || true

    echo
    read -r -p "Press Enter after Tailscale auth is complete..."

    if tailscale_is_authenticated; then
      echo "Tailscale authentication confirmed"
      return 0
    else
      echo "Tailscale still does not appear authenticated"
      echo "Continuing install, but initial maintain pass will be skipped"
      return 1
    fi
    ;;

  3)
    echo "Skipping Tailscale auth for now"
    return 1
    ;;

  *)
    echo "Invalid choice; skipping auth"
    return 1
    ;;
  esac
}

echo "Checking/installing dependencies"
apt-get update

if ! command -v curl >/dev/null 2>&1; then
  apt-get install -y curl
fi

if ! command -v ethtool >/dev/null 2>&1; then
  apt-get install -y ethtool
fi

echo "Installing Tailscale if needed"
install_tailscale_if_needed

echo "Securing role directory"
chown -R root:root "$ROLE_DIR"
chmod 700 "$ROLE_DIR"
chmod 600 "$ENV_FILE"
chmod 700 "$ROLE_DIR/bin" "$ROLE_DIR/systemd" "$ROLE_DIR/addons"
chmod 700 "$ROLE_DIR/bin/"*.sh
chmod 700 "$ROLE_DIR/addons/"*.sh 2>/dev/null || true
chmod 700 "$ROLE_DIR/install.sh" "$ROLE_DIR/uninstall.sh"

echo "Installing systemd units"
install -m 0644 "$ROLE_DIR/systemd/pi-tailscale-maintain.service" /etc/systemd/system/pi-tailscale-maintain.service
install -m 0644 "$ROLE_DIR/systemd/pi-tailscale-maintain.timer" /etc/systemd/system/pi-tailscale-maintain.timer
install -m 0644 "$ROLE_DIR/systemd/pi-tailscale-health.service" /etc/systemd/system/pi-tailscale-health.service
install -m 0644 "$ROLE_DIR/systemd/pi-tailscale-health.timer" /etc/systemd/system/pi-tailscale-health.timer

echo "Installing tailscaled restart override"
install -d -m 0755 /etc/systemd/system/tailscaled.service.d

cat >/etc/systemd/system/tailscaled.service.d/override.conf <<'EOF'
[Service]
Restart=always
RestartSec=10
StartLimitIntervalSec=0
EOF

echo "Enabling forwarding"
cat >/etc/sysctl.d/99-pi-tailscale-role.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sysctl --system >/dev/null

echo "Reloading systemd"
systemctl daemon-reload

echo "Enabling tailscaled"
systemctl enable --now tailscaled

AUTH_OK="false"

if authenticate_tailscale_if_needed; then
  AUTH_OK="true"
fi

echo "Enabling timers"
systemctl enable --now pi-tailscale-maintain.timer
systemctl enable --now pi-tailscale-health.timer

if [[ "$AUTH_OK" == "true" ]] || tailscale_is_authenticated; then
  echo "Running initial maintain pass"
  systemctl start pi-tailscale-maintain.service
else
  echo "Skipping initial maintain pass until Tailscale is authenticated"
  echo
  echo "After authenticating later, run:"
  echo "  sudo systemctl start pi-tailscale-maintain.service"
fi

echo
echo "Installed pi-tailscale-role."
echo
echo "Live role directory:"
echo "  $ROLE_DIR"
echo
echo "Env file:"
echo "  $ENV_FILE"
echo
echo "Check with:"
echo "  systemctl list-timers 'pi-tailscale-*'"
echo "  journalctl -u pi-tailscale-maintain.service -n 50 --no-pager"
echo "  journalctl -u pi-tailscale-health.service -n 50 --no-pager"
echo "  tailscale status"
echo
echo "If routes or exit-node changed, approve them in the Tailscale admin console unless the auth key/policy auto-approves them."
