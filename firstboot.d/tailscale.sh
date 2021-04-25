#!/bin/sh

set -e

# Symlink the state directory to /config to preserve across reboots/upgrades
mkdir -p /config/tailscale/state
ln -s /config/tailscale/state /var/lib/tailscale

if [ ! -L /etc/systemd/system/tailscaled.service.d ]; then
	ln -s /config/tailscale/systemd/tailscaled.service.d /etc/systemd/system/tailscaled.service.d
fi

# Ensure there is a post-config script to install the tailscale package
mkdir -p /config/scripts/post-config.d
if [ ! -x /config/scripts/post-config.d/tailscale.sh ]; then
	cat > /config/scripts/post-config.d/tailscale.sh <<EOF
#!/bin/sh

set -e

if ! gpg --list-keys --with-colons --keyring /etc/apt/trusted.gpg | grep -qF info@tailscale.com; then
	if [ ! -e /config/tailscale/stretch.gpg ]; then
		curl -fsSLo /config/tailscale/stretch.gpg https://pkgs.tailscale.com/stable/debian/stretch.gpg
	fi
	apt-key add /config/tailscale/stretch.gpg >/dev/null 2>&1
fi
if ! dpkg-query -Wf '${Status}' tailscale 2>/dev/null | grep -qF "install ok installed"; then
	apt-get update
	apt-get install tailscale
	mkdir -p /config/data/firstboot/install-packages
	cp /var/cache/apt/archives/tailscale_*.deb /config/data/firstboot/install-packages
fi
EOF
	chmod 755 /config/scripts/post-config.d/tailscale.sh
fi
