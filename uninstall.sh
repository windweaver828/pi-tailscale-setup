#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root: sudo ./uninstall.sh" >&2
    exit 1
fi

systemctl disable --now pi-tailscale-maintain.timer 2>/dev/null || true
systemctl disable --now pi-tailscale-health.timer 2>/dev/null || true

rm -f /etc/systemd/system/pi-tailscale-maintain.service
rm -f /etc/systemd/system/pi-tailscale-maintain.timer
rm -f /etc/systemd/system/pi-tailscale-health.service
rm -f /etc/systemd/system/pi-tailscale-health.timer

rm -f /usr/local/sbin/pi-tailscale-maintain.sh
rm -f /usr/local/sbin/pi-tailscale-health.sh

rm -f /etc/sysctl.d/99-pi-tailscale-role.conf
rm -f /etc/systemd/system/tailscaled.service.d/override.conf

systemctl daemon-reload

echo "Removed pi-tailscale-role files."
echo "Tailscale itself was not uninstalled."
echo "Config directory kept at:"
echo "  /etc/pi-tailscale-role"
