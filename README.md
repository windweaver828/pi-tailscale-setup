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


## Use email addon
sudo apt install -y swaks
sudo mkdir -p /root/utils
sudo cp addons/email/email.sh.example /root/utils/email.sh
sudo chmod 700 /root/utils/email.sh
sudo cp addons/email/env-email.example /root/utils/.env-email
sudo vi /root/utils/.env-email
sudo chmod 600 /root/utils/.env-email
