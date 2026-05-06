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
- expects system mail to be setup to forward to real email for alerts 
- for system mail forward setup see https://github.com/windweaver828/linux-utils.git email -> system-mail
- optionally call a Nextcloud-based reauth addon after repeated failures

## Install

This role expects to live at: /root/pi-tailscale-role

## Install

```bash
sudo apt update
sudo apt install -y git

git clone https://github.com/windweaver828/pi-tailscale-role.git
cd pi-tailscale-role

cp env.example .env
vi .env

sudo bash install.sh
