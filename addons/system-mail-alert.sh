#!/usr/bin/env bash
set -euo pipefail

SUBJECT="${1:-Pi Tailscale alert on $(hostname)}"
BODY="${2:-}"

# Prevent accidental header injection.
SUBJECT="${SUBJECT//$'\r'/ }"
SUBJECT="${SUBJECT//$'\n'/ }"

if [[ -z "$BODY" ]]; then
  echo "Usage: $0 'Subject' 'Message body'" >&2
  exit 1
fi

if ! command -v mail >/dev/null 2>&1; then
  echo "mail command not found; system mail is not configured or mailx is not installed" >&2
  exit 1
fi

printf '%s\n' "$BODY" | mail -s "$SUBJECT" root
