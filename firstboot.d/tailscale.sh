#!/bin/sh
ln -s /config/tailscale/systemd/tailscaled.service /etc/systemd/system/tailscaled.service
ln -s /config/tailscale/systemd/tailscaled.service.d /etc/systemd/system/tailscaled.service.d
ln -s /config/tailscale/systemd/tailscaled.defaults /etc/default/tailscaled
ln -s /config/tailscale/tailscale /usr/bin/tailscale
ln -s /config/tailscale/tailscaled /usr/sbin/tailscaled
mkdir -p /var/lib/tailscale
touch /config/auth/tailscaled.state
chmod 0400 /config/auth/tailscaled.state
ln -s /config/auth/tailscaled.state /var/lib/tailscale/tailscaled.state
systemctl enable --now tailscaled
