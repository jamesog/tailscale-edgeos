#!/bin/sh

set -e

mkdir -p /config/tailscale/systemd/tailscaled.service.d
mkdir -p /config/tailscale/state

# Create a bind mount for the Tailscale state directory
if [ ! -f /config/tailscale/systemd/var-lib-tailscale.mount ]; then
	cat > /config/tailscale/systemd/var-lib-tailscale.mount <<-EOF
[Mount]
What=/config/tailscale/state
Where=/var/lib/tailscale
Type=none
Options=bind

[Install]
WantedBy=multi-user.target
	EOF
fi

# Add an override to tailscaled.service to require the bind mount
if [ ! -f /config/tailscale/systemd/tailscaled.service.d/mount.conf ]; then
	cat > /config/tailscale/systemd/tailscaled.service.d/mount.conf <<-EOF
[Unit]
RequiresMountsFor=/var/lib/tailscale
	EOF
fi
# Add an override to tailscaled.service to wait until "UBNT Routing Daemons"
# has finished, otherwise tailscaled won't have proper networking
if [ ! -f /config/tailscale/systemd/tailscaled.service.d/wait-for-networking.conf ]; then
	cat > /config/tailscale/systemd/tailscaled.service.d/wait-for-networking.conf <<-EOF
[Unit]
Wants=vyatta-router.service
After=vyatta-router.service
	EOF
fi

if [ ! -L /etc/systemd/system/tailscaled.service.d ]; then
	ln -s /config/tailscale/systemd/tailscaled.service.d /etc/systemd/system/tailscaled.service.d
fi
systemctl daemon-reload

# Ensure there is a post-config script to install Tailscale
mkdir -p /config/scripts/post-config.d
if [ ! -x /config/scripts/post-config.d/tailscale.sh ]; then
	cat > /config/scripts/post-config.d/tailscale.sh <<"EOF"
#!/bin/sh

set -e

reload=""
apt_index_updated=""

# The mount unit needs to be copied rather than linked.
# systemd errors with "Link has been severed" if the unit is a symlink.
if [ ! -f /etc/systemd/system/var-lib-tailscale.mount ]; then
	echo Installing /var/lib/tailscale mount unit
	cp /config/tailscale/systemd/var-lib-tailscale.mount /etc/systemd/system/var-lib-tailscale.mount
	reload=y
fi

if [ ! -L /etc/systemd/system/tailscaled.service.d ]; then
	ln -s /config/tailscale/systemd/tailscaled.service.d /etc/systemd/system/tailscaled.service.d
	reload=y
fi

if [ -n "$reload" ]; then
	# Ensure systemd has loaded the unit overrides
	systemctl daemon-reload
fi

KEYRING=/usr/share/keyrings/tailscale-archive-keyring.gpg

if ! gpg --list-keys --with-colons --keyring $KEYRING 2>/dev/null | grep -qF info@tailscale.com; then
	echo Installing Tailscale repository signing key
	apt-get update --allow-unauthenticated
	apt_index_updated=y
	apt-get install --allow-unauthenticated tailscale-archive-keyring
	if [ -e /config/tailscale/stretch.gpg ]; then
		# Clean up pre tailscale-archive-keyring data
		rm /config/tailscale/stretch.gpg
	fi
fi

pkg_status=$(dpkg-query -Wf '${Status}' tailscale 2>/dev/null || true)
if ! echo $pkg_status| grep -qF "install ok installed"; then
	# Sometimes after a firmware upgrade the package goes into half-configured state
	if echo $pkg_status | grep -qF "half-configured"; then
		# Use systemd-run to configure the package in a separate unit, otherwise it will block
		# due to tailscaled.service waiting on vyatta-router.service, which is running this script.
		systemd-run --no-block dpkg --configure -a
	else
		echo "Installing Tailscale"
		[[ -z "$apt_index_updated" ]] && apt-get update
		apt-get install tailscale
		mkdir -p /config/data/firstboot/install-packages
		cp /var/cache/apt/archives/tailscale_*.deb /config/data/firstboot/install-packages
	fi
fi

if [ -n "$reload" ]; then
	systemctl --no-block restart tailscaled
fi
EOF
	chmod 755 /config/scripts/post-config.d/tailscale.sh
fi
