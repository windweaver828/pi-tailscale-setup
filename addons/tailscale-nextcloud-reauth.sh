#!/usr/bin/env bash
set -euo pipefail

ROLE_DIR="/root/pi-tailscale-role"
ENV_FILE="$ROLE_DIR/.env"
LOG_TAG="tailscale-nextcloud-reauth"

log() {
  logger -t "$LOG_TAG" "$*"
  echo "$*"
}

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
else
  log "Missing env file: $ENV_FILE"
  exit 1
fi

: "${NC_WEBDAV_URL:?Missing NC_WEBDAV_URL}"
: "${NC_USER:?Missing NC_USER}"
: "${NC_APP_PASSWORD:?Missing NC_APP_PASSWORD}"

PI_TS_HOSTNAME="${PI_TS_HOSTNAME:-$(hostname)}"
PI_TS_ACCEPT_DNS="${PI_TS_ACCEPT_DNS:-false}"
PI_TS_ACCEPT_ROUTES="${PI_TS_ACCEPT_ROUTES:-false}"
PI_TS_EXTRA_UP_ARGS="${PI_TS_EXTRA_UP_ARGS:-}"

PI_TS_ADVERTISE_EXIT_NODE="${PI_TS_ADVERTISE_EXIT_NODE:-false}"
PI_TS_ADVERTISE_DYNAMIC_LAN="${PI_TS_ADVERTISE_DYNAMIC_LAN:-false}"
PI_TS_STATIC_ROUTES="${PI_TS_STATIC_ROUTES:-}"

if ! command -v curl >/dev/null 2>&1; then
  log "curl is not installed"
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  log "tailscale command not found"
  exit 1
fi

KEY="$(
  curl -fsSL \
    --connect-timeout 20 \
    --max-time 60 \
    --user "${NC_USER}:${NC_APP_PASSWORD}" \
    "$NC_WEBDAV_URL" |
    tr -d '\r\n[:space:]'
)"

if [[ -z "$KEY" || "$KEY" == "NONE" || "$KEY" == "none" ]]; then
  log "No reauth key available"
  exit 1
fi

if [[ "$KEY" != tskey-auth-* ]]; then
  log "Downloaded content does not look like a Tailscale auth key"
  exit 1
fi

DEV="$(
  ip -4 route show default 0.0.0.0/0 |
    awk '$5 != "tailscale0" { print $5; exit }'
)"

if [[ -z "${DEV:-}" ]]; then
  log "No non-Tailscale default IPv4 interface found"
  exit 1
fi

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
fi

ADVERTISE_ROUTES=""

if [[ -n "$PI_TS_STATIC_ROUTES" && "$PI_TS_ADVERTISE_DYNAMIC_LAN" == "true" ]]; then
  ADVERTISE_ROUTES="${PI_TS_STATIC_ROUTES},${DYNAMIC_LAN}"
elif [[ -n "$PI_TS_STATIC_ROUTES" ]]; then
  ADVERTISE_ROUTES="$PI_TS_STATIC_ROUTES"
elif [[ "$PI_TS_ADVERTISE_DYNAMIC_LAN" == "true" ]]; then
  ADVERTISE_ROUTES="$DYNAMIC_LAN"
fi

log "Downloaded possible Tailscale auth key; attempting reauth"

args=(
  up
  "--auth-key=${KEY}"
  "--hostname=${PI_TS_HOSTNAME}"
  "--accept-dns=${PI_TS_ACCEPT_DNS}"
  "--accept-routes=${PI_TS_ACCEPT_ROUTES}"
)

if [[ "$PI_TS_ADVERTISE_EXIT_NODE" == "true" ]]; then
  args+=("--advertise-exit-node")
fi

if [[ -n "$ADVERTISE_ROUTES" ]]; then
  args+=("--advertise-routes=${ADVERTISE_ROUTES}")
else
  args+=("--advertise-routes=")
fi

if [[ -n "$PI_TS_EXTRA_UP_ARGS" ]]; then
  # shellcheck disable=SC2206
  extra_args=($PI_TS_EXTRA_UP_ARGS)
  args+=("${extra_args[@]}")
fi

if tailscale "${args[@]}"; then
  log "Tailscale reauth succeeded"
  systemctl start pi-tailscale-maintain.service || true
  exit 0
fi

log "Tailscale reauth failed"
exit 1
