#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/pi-tailscale-role/pi-tailscale.conf"
LOG_TAG="pi-tailscale-health"
FAIL_FILE="/run/pi-tailscale-health.failures"

log() {
    logger -t "$LOG_TAG" "$*"
    echo "$*"
}

if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
fi

PI_TS_RESTART_ON_HEALTH_FAIL="${PI_TS_RESTART_ON_HEALTH_FAIL:-true}"
PI_TS_REBOOT_ON_REPEATED_FAILURE="${PI_TS_REBOOT_ON_REPEATED_FAILURE:-false}"
PI_TS_MAX_FAILURES_BEFORE_REBOOT="${PI_TS_MAX_FAILURES_BEFORE_REBOOT:-8}"

record_failure() {
    local count=0

    if [[ -f "$FAIL_FILE" ]]; then
        count="$(cat "$FAIL_FILE" 2>/dev/null || echo 0)"
    fi

    count=$((count + 1))
    echo "$count" > "$FAIL_FILE"

    log "Failure count: $count/$PI_TS_MAX_FAILURES_BEFORE_REBOOT"

    if [[ "$PI_TS_REBOOT_ON_REPEATED_FAILURE" == "true" ]] && \
       (( count >= PI_TS_MAX_FAILURES_BEFORE_REBOOT )); then
        log "Repeated Tailscale failure; rebooting"
        systemctl reboot
    fi
}

reset_failures() {
    rm -f "$FAIL_FILE"
}

restart_tailscaled() {
    log "$1"

    if [[ "$PI_TS_RESTART_ON_HEALTH_FAIL" == "true" ]]; then
        systemctl restart tailscaled || true
    fi

    record_failure
}

if ! command -v tailscale >/dev/null 2>&1; then
    log "tailscale command not found"
    exit 1
fi

if ! systemctl is-active --quiet tailscaled; then
    restart_tailscaled "tailscaled inactive"
    exit 0
fi

if ! tailscale ip -4 >/dev/null 2>&1; then
    restart_tailscaled "tailscale has no IPv4 address"
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    STATE="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"')"

    if [[ "$STATE" != "Running" ]]; then
        restart_tailscaled "tailscale backend state is $STATE"
        exit 0
    fi
fi

log "Tailscale appears healthy"
reset_failures
