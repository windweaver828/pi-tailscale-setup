#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/pi-tailscale-role/pi-tailscale.conf"
LOG_TAG="pi-tailscale-maintain"

log() {
    logger -t "$LOG_TAG" "$*"
    echo "$*"
}

if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
else
    log "Missing config: $CONF"
    exit 1
fi

PI_TS_HOSTNAME="${PI_TS_HOSTNAME:-$(hostname)}"
PI_TS_ADVERTISE_EXIT_NODE="${PI_TS_ADVERTISE_EXIT_NODE:-false}"
PI_TS_ADVERTISE_DYNAMIC_LAN="${PI_TS_ADVERTISE_DYNAMIC_LAN:-false}"
PI_TS_STATIC_ROUTES="${PI_TS_STATIC_ROUTES:-}"
PI_TS_ACCEPT_DNS="${PI_TS_ACCEPT_DNS:-false}"
PI_TS_ACCEPT_ROUTES="${PI_TS_ACCEPT_ROUTES:-false}"
PI_TS_APPLY_PERFORMANCE="${PI_TS_APPLY_PERFORMANCE:-true}"

if ! command -v tailscale >/dev/null 2>&1; then
    log "tailscale command not found"
    exit 1
fi

if ! systemctl is-active --quiet tailscaled; then
    log "tailscaled inactive; restarting"
    systemctl restart tailscaled
    sleep 5
fi

DEV="$(
    ip -4 route show default 0.0.0.0/0 |
    awk '$5 != "tailscale0" { print $5; exit }'
)"

if [[ -z "${DEV:-}" ]]; then
    log "No non-Tailscale default IPv4 interface found"
    exit 1
fi

log "Default IPv4 interface: $DEV"

DYNAMIC_LAN=""

if [[ "$PI_TS_ADVERTISE_DYNAMIC_LAN" == "true" ]]; then
    DYNAMIC_LAN="$(
        ip -4 route show dev "$DEV" scope link proto kernel |
        awk '{ print $1; exit }'
    )"

    if [[ -z "${DYNAMIC_LAN:-}" ]]; then
        log "No connected LAN route found for $DEV"
        exit 1
    fi

    log "Detected dynamic LAN route: $DYNAMIC_LAN"
fi

if [[ "$PI_TS_APPLY_PERFORMANCE" == "true" ]]; then
    if command -v ethtool >/dev/null 2>&1; then
        log "Applying Tailscale performance settings to $DEV"
        ethtool -K "$DEV" rx-udp-gro-forwarding on rx-gro-list off || \
            log "Warning: ethtool tuning failed on $DEV"
    else
        log "Warning: ethtool not installed"
    fi
fi

ADVERTISE_ROUTES=""

if [[ -n "$PI_TS_STATIC_ROUTES" && "$PI_TS_ADVERTISE_DYNAMIC_LAN" == "true" ]]; then
    ADVERTISE_ROUTES="${PI_TS_STATIC_ROUTES},${DYNAMIC_LAN}"
elif [[ -n "$PI_TS_STATIC_ROUTES" ]]; then
    ADVERTISE_ROUTES="$PI_TS_STATIC_ROUTES"
elif [[ "$PI_TS_ADVERTISE_DYNAMIC_LAN" == "true" ]]; then
    ADVERTISE_ROUTES="$DYNAMIC_LAN"
fi

ARGS=(
    set
    "--hostname=${PI_TS_HOSTNAME}"
    "--accept-dns=${PI_TS_ACCEPT_DNS}"
    "--accept-routes=${PI_TS_ACCEPT_ROUTES}"
)

if [[ "$PI_TS_ADVERTISE_EXIT_NODE" == "true" ]]; then
    ARGS+=("--advertise-exit-node")
fi

if [[ -n "$ADVERTISE_ROUTES" ]]; then
    ARGS+=("--advertise-routes=${ADVERTISE_ROUTES}")
else
    ARGS+=("--advertise-routes=")
fi

log "Applying Tailscale desired state"
tailscale "${ARGS[@]}"

log "Tailscale desired state applied"
