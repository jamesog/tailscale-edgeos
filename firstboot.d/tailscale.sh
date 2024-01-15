#!/bin/sh

set -e

sed -i 's|^mozilla\/DST_Root_CA_X3\.crt|!mozilla/DST_Root_CA_X3.crt|' /etc/ca-certificates.conf
mkdir -p /usr/local/share/ca-certificates/
curl -sk https://letsencrypt.org/certs/isrgrootx1.pem -o /usr/local/share/ca-certificates/ISRG_Root_X1.crt
update-ca-certificates --fresh

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

KEYRING=/usr/share/keyrings/tailscale-stretch-stable.gpg

if ! gpg --list-keys --with-colons --keyring $KEYRING 2>/dev/null | grep -qF info@tailscale.com; then
	echo Installing Tailscale repository signing key
	if [ ! -e /config/tailscale/stretch.gpg ]; then
		curl -fsSL https://pkgs.tailscale.com/stable/debian/stretch.asc | gpg --dearmor > /config/tailscale/stretch.gpg
	fi
	cp /config/tailscale/stretch.gpg $KEYRING
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
		apt-get update
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
