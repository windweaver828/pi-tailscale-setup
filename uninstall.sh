#!/usr/bin/env bash
set -euo pipefail

ROLE_DIR="/root/pi-tailscale-role"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./uninstall.sh" >&2
  exit 1
fi

echo "Stopping and disabling pi-tailscale-role timers"
systemctl disable --now pi-tailscale-maintain.timer 2>/dev/null || true
systemctl disable --now pi-tailscale-health.timer 2>/dev/null || true

echo "Removing pi-tailscale-role systemd units"
rm -f /etc/systemd/system/pi-tailscale-maintain.service
rm -f /etc/systemd/system/pi-tailscale-maintain.timer
rm -f /etc/systemd/system/pi-tailscale-health.service
rm -f /etc/systemd/system/pi-tailscale-health.timer

echo "Removing forwarding sysctl config"
rm -f /etc/sysctl.d/99-pi-tailscale-role.conf

echo "Removing tailscaled restart override installed by this role"
rm -f /etc/systemd/system/tailscaled.service.d/override.conf
rmdir /etc/systemd/system/tailscaled.service.d 2>/dev/null || true

echo "Reloading systemd"
systemctl daemon-reload

echo "Reloading sysctl settings"
sysctl --system >/dev/null || true

echo
echo "Removed installed pi-tailscale-role system integration."
echo
echo "Kept:"
echo "  Tailscale itself"
echo "  $ROLE_DIR"
echo "  optional external hooks like /root/utils/email.sh"
echo
echo "To remove the cloned role directory too, run:"
echo "  sudo rm -rf $ROLE_DIR"
