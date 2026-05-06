#!/usr/bin/env bash
set -euo pipefail

ROLE_DIR="/root/pi-tailscale-role"
ENV_FILE="$ROLE_DIR/.env"
LOG_TAG="pi-tailscale-health"
FAIL_FILE="/run/pi-tailscale-health.failures"
EMAIL_STAMP_FILE="/run/pi-tailscale-health.last-email-alert"
REAUTH_STAMP_FILE="/run/pi-tailscale-health.last-reauth-attempt"

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

PI_TS_RESTART_ON_HEALTH_FAIL="${PI_TS_RESTART_ON_HEALTH_FAIL:-true}"
PI_TS_REBOOT_ON_REPEATED_FAILURE="${PI_TS_REBOOT_ON_REPEATED_FAILURE:-false}"
PI_TS_MAX_FAILURES_BEFORE_REBOOT="${PI_TS_MAX_FAILURES_BEFORE_REBOOT:-8}"

PI_TS_EMAIL_COMMAND="${PI_TS_EMAIL_COMMAND:-}"
PI_TS_EMAIL_AFTER_FAILURES="${PI_TS_EMAIL_AFTER_FAILURES:-3}"
PI_TS_EMAIL_COOLDOWN_SECONDS="${PI_TS_EMAIL_COOLDOWN_SECONDS:-3600}"

PI_TS_REAUTH_COMMAND="${PI_TS_REAUTH_COMMAND:-}"
PI_TS_REAUTH_AFTER_FAILURES="${PI_TS_REAUTH_AFTER_FAILURES:-5}"
PI_TS_REAUTH_COOLDOWN_SECONDS="${PI_TS_REAUTH_COOLDOWN_SECONDS:-900}"

send_email_alert_if_needed() {
  local count="$1"
  local reason="$2"

  if [[ -z "$PI_TS_EMAIL_COMMAND" ]]; then
    return 0
  fi

  if ((count < PI_TS_EMAIL_AFTER_FAILURES)); then
    return 0
  fi

  if [[ ! -x "$PI_TS_EMAIL_COMMAND" ]]; then
    log "Email command configured but missing or not executable: $PI_TS_EMAIL_COMMAND"
    return 0
  fi

  local now
  now="$(date +%s)"

  local last=0
  if [[ -f "$EMAIL_STAMP_FILE" ]]; then
    last="$(cat "$EMAIL_STAMP_FILE" 2>/dev/null || echo 0)"
  fi

  local elapsed=$((now - last))

  if ((elapsed < PI_TS_EMAIL_COOLDOWN_SECONDS)); then
    log "Email alert suppressed by cooldown"
    return 0
  fi

  echo "$now" >"$EMAIL_STAMP_FILE"

  local subject
  subject="Tailscale issue on $(hostname)"

  local body
  body="$(
    cat <<EOF
Tailscale health problem detected.

Host: $(hostname)
Time: $(date --iso-8601=seconds)
Reason: $reason
Consecutive failures: $count

tailscaled active state:
$(systemctl is-active tailscaled 2>&1 || true)

Tailscale IP:
$(tailscale ip -4 2>&1 || true)

Tailscale status:
$(tailscale status 2>&1 || true)

Recent health logs:
$(journalctl -u pi-tailscale-health.service -n 30 --no-pager 2>&1 || true)
EOF
  )"

  if "$PI_TS_EMAIL_COMMAND" "$subject" "$body"; then
    log "Email alert sent"
  else
    log "Warning: email alert command failed"
  fi
}

try_reauth_if_needed() {
  local count="$1"
  local reason="$2"

  if [[ -z "$PI_TS_REAUTH_COMMAND" ]]; then
    return 1
  fi

  if ((count < PI_TS_REAUTH_AFTER_FAILURES)); then
    return 1
  fi

  if [[ ! -x "$PI_TS_REAUTH_COMMAND" ]]; then
    log "Reauth command configured but missing or not executable: $PI_TS_REAUTH_COMMAND"
    return 1
  fi

  local now
  now="$(date +%s)"

  local last=0
  if [[ -f "$REAUTH_STAMP_FILE" ]]; then
    last="$(cat "$REAUTH_STAMP_FILE" 2>/dev/null || echo 0)"
  fi

  local elapsed=$((now - last))

  if ((elapsed < PI_TS_REAUTH_COOLDOWN_SECONDS)); then
    log "Reauth attempt suppressed by cooldown"
    return 1
  fi

  echo "$now" >"$REAUTH_STAMP_FILE"

  log "Attempting reauth after $count failures: $reason"

  if "$PI_TS_REAUTH_COMMAND"; then
    log "Reauth command succeeded"
    reset_failures
    return 0
  fi

  log "Reauth command failed"
  return 1
}

record_failure() {
  local reason="${1:-unknown failure}"
  local count=0

  if [[ -f "$FAIL_FILE" ]]; then
    count="$(cat "$FAIL_FILE" 2>/dev/null || echo 0)"
  fi

  count=$((count + 1))
  echo "$count" >"$FAIL_FILE"

  log "Failure count: $count/$PI_TS_MAX_FAILURES_BEFORE_REBOOT"

  if try_reauth_if_needed "$count" "$reason"; then
    return 0
  fi

  send_email_alert_if_needed "$count" "$reason"

  if [[ "$PI_TS_REBOOT_ON_REPEATED_FAILURE" == "true" ]] &&
    ((count >= PI_TS_MAX_FAILURES_BEFORE_REBOOT)); then
    log "Repeated Tailscale failure; rebooting"
    systemctl reboot
  fi
}

reset_failures() {
  rm -f "$FAIL_FILE"
}

restart_tailscaled() {
  local reason="${1:-unknown failure}"

  log "$reason"

  if [[ "$PI_TS_RESTART_ON_HEALTH_FAIL" == "true" ]]; then
    systemctl restart tailscaled || true
  fi

  record_failure "$reason"
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

if ! tailscale status >/dev/null 2>&1; then
  restart_tailscaled "tailscale status command failed"
  exit 0
fi

log "Tailscale appears healthy"
reset_failures
