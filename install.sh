#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_SRC="$SRC_DIR/pi-tailscale.conf"
CONF_EXAMPLE="$SRC_DIR/pi-tailscale.conf.example"
CONF_DIR="/etc/pi-tailscale-role"
CONF_DST="$CONF_DIR/pi-tailscale.conf"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root: sudo ./install.sh" >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This installer currently supports Debian/Raspberry Pi OS systems with apt-get." >&2
    exit 1
fi

if [[ ! -f "$CONF_SRC" ]]; then
    if [[ -f "$CONF_EXAMPLE" ]]; then
        cp "$CONF_EXAMPLE" "$CONF_SRC"
        chmod 0600 "$CONF_SRC"
        echo "Created local config:"
        echo "  $CONF_SRC"
        echo
        echo "Edit it, then rerun:"
        echo "  sudo ./install.sh"
        exit 1
    else
        echo "Missing config: $CONF_SRC" >&2
        exit 1
    fi
fi

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

tailscale_backend_state() {
    if ! command -v tailscale >/dev/null 2>&1; then
        echo "missing"
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown"
    else
        if tailscale ip -4 >/dev/null 2>&1; then
            echo "Running"
        else
            echo "unknown"
        fi
    fi
}

tailscale_is_authenticated() {
    local state
    state="$(tailscale_backend_state)"

    [[ "$state" == "Running" ]]
}

authenticate_tailscale_if_needed() {
    echo "Checking Tailscale authentication state"

    if tailscale_is_authenticated; then
        echo "Tailscale already authenticated"
        return 0
    fi

    if [[ -n "${PI_TS_AUTH_KEY:-}" ]]; then
        echo "Tailscale not authenticated; using configured auth key"

        tailscale up \
            --auth-key="$PI_TS_AUTH_KEY" \
            --hostname="$PI_TS_HOSTNAME" \
            --accept-dns="$PI_TS_ACCEPT_DNS" \
            --accept-routes="$PI_TS_ACCEPT_ROUTES" \
            ${PI_TS_EXTRA_UP_ARGS}

        echo "Tailscale authenticated with configured auth key"
        return 0
    fi

    echo
    echo "Tailscale is installed but not authenticated."
    echo "No PI_TS_AUTH_KEY is set in:"
    echo "  $CONF_DST"
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

            tailscale up \
                --auth-key="$entered_key" \
                --hostname="$PI_TS_HOSTNAME" \
                --accept-dns="$PI_TS_ACCEPT_DNS" \
                --accept-routes="$PI_TS_ACCEPT_ROUTES" \
                ${PI_TS_EXTRA_UP_ARGS}

            echo "Tailscale authenticated with provided auth key"
            return 0
            ;;

        2)
            echo
            echo "Starting normal Tailscale auth."
            echo "Open the auth URL shown below, finish login/approval, then come back here."
            echo

            tailscale up \
                --hostname="$PI_TS_HOSTNAME" \
                --accept-dns="$PI_TS_ACCEPT_DNS" \
                --accept-routes="$PI_TS_ACCEPT_ROUTES" \
                ${PI_TS_EXTRA_UP_ARGS} || true

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

echo "Checking/Installing dependencies"
apt-get update
if ! command -v ethtool && command -v jq >/dev/null 2>&1; then
    apt-get install -y ethtool jq
fi

echo "Installing Tailscale if needed"
install_tailscale_if_needed

echo "Installing config"
install -d -m 0755 "$CONF_DIR"

# Use 0600 because the config may contain a Tailscale auth key.
install -m 0600 "$CONF_SRC" "$CONF_DST"

# Load config after copying it to the final location.
# shellcheck source=/dev/null
source "$CONF_DST"

PI_TS_HOSTNAME="${PI_TS_HOSTNAME:-$(hostname)}"
PI_TS_AUTH_KEY="${PI_TS_AUTH_KEY:-}"
PI_TS_EXTRA_UP_ARGS="${PI_TS_EXTRA_UP_ARGS:-}"
PI_TS_ACCEPT_DNS="${PI_TS_ACCEPT_DNS:-false}"
PI_TS_ACCEPT_ROUTES="${PI_TS_ACCEPT_ROUTES:-false}"
PI_TS_EMAIL_ALERTS="${PI_TS_EMAIL_ALERTS:-false}"

if [[ "$PI_TS_EMAIL_ALERTS" == "true" ]]; then
    if ! command -v swaks >/dev/null 2>&1; then
        echo "Email alerts enabled and swaks not found; installing swaks"
        apt-get install -y swaks
    fi
fi

echo "Installing scripts"
install -m 0755 "$SRC_DIR/bin/pi-tailscale-maintain.sh" /usr/local/sbin/pi-tailscale-maintain.sh
install -m 0755 "$SRC_DIR/bin/pi-tailscale-health.sh" /usr/local/sbin/pi-tailscale-health.sh

echo "Installing systemd units"
install -m 0644 "$SRC_DIR/systemd/pi-tailscale-maintain.service" /etc/systemd/system/pi-tailscale-maintain.service
install -m 0644 "$SRC_DIR/systemd/pi-tailscale-maintain.timer" /etc/systemd/system/pi-tailscale-maintain.timer
install -m 0644 "$SRC_DIR/systemd/pi-tailscale-health.service" /etc/systemd/system/pi-tailscale-health.service
install -m 0644 "$SRC_DIR/systemd/pi-tailscale-health.timer" /etc/systemd/system/pi-tailscale-health.timer

echo "Installing tailscaled restart override"
install -d -m 0755 /etc/systemd/system/tailscaled.service.d

cat > /etc/systemd/system/tailscaled.service.d/override.conf <<'EOT'
[Service]
Restart=always
RestartSec=10
StartLimitIntervalSec=0
EOT

echo "Enabling forwarding"
cat > /etc/sysctl.d/99-pi-tailscale-role.conf <<'EOT'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOT

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
echo "Config installed at:"
echo "  $CONF_DST"
echo
echo "Check with:"
echo "  systemctl list-timers 'pi-tailscale-*'"
echo "  journalctl -u pi-tailscale-maintain.service -n 50 --no-pager"
echo "  journalctl -u pi-tailscale-health.service -n 50 --no-pager"
echo "  tailscale status"
echo
echo "If routes or exit-node changed, approve them in the Tailscale admin console unless the auth key/policy auto-approves them."
