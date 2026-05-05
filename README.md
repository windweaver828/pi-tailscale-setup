# pi-tailscale-role

Reusable Raspberry Pi / Debian role for keeping a Tailscale node configured and self-healing.

It can:

- install Tailscale if missing
- authenticate using a pasted auth key, configured auth key, or normal browser/device auth
- advertise the current LAN subnet dynamically
- advertise the Pi as an exit node
- apply Tailscale Linux performance tuning with `ethtool`
- periodically re-apply desired Tailscale settings
- restart `tailscaled` if it becomes unhealthy

## Install

```bash
sudo apt update
sudo apt install -y git

git clone https://github.com/windweaver828/pi-tailscale-role.git
cd pi-tailscale-role

cp pi-tailscale.conf.example pi-tailscale.conf
vi pi-tailscale.conf

sudo bash install.sh
