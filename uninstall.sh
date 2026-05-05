#!/usr/bin/env bash
set -euo pipefail

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

echo "Removing installed pi-tailscale-role scripts"
rm -f /usr/local/sbin/pi-tailscale-maintain.sh
rm -f /usr/local/sbin/pi-tailscale-health.sh

echo "Removing forwarding sysctl config"
rm -f /etc/sysctl.d/99-pi-tailscale-role.conf

echo "Removing tailscaled restart override installed by this role"
rm -f /etc/systemd/system/tailscaled.service.d/override.conf

# Remove the override directory only if empty.
rmdir /etc/systemd/system/tailscaled.service.d 2>/dev/null || true

echo "Reloading systemd"
systemctl daemon-reload

echo "Reloading sysctl settings"
sysctl --system >/dev/null || true

echo
echo "Removed pi-tailscale-role files."
echo
echo "Kept:"
echo "  Tailscale itself"
echo "  /etc/pi-tailscale-role/"
echo "  any optional external email hook such as /root/utils/email.sh"
echo
echo "If one wants to remove the role config too, run:"
echo "  sudo rm -rf /etc/pi-tailscale-role"
