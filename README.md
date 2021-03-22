# Tailscale on EdgeOS

This is a short guide for getting [Tailscale](https://tailscale.com/) running on the Ubiquiti EdgeRouter platform. EdgeOS 2.0+ is required to make use of the systemd unit file shipped by Tailscale.

This is based on [lg](https://github.com/lg)'s [gist](https://gist.github.com/lg/6f80593bd55ca9c9cf886da169a972c3), although the `firstboot` here script is a modified version of [joeshaw](https://github.com/joeshaw)'s [suggestion](https://gist.github.com/lg/6f80593bd55ca9c9cf886da169a972c3#gistcomment-3578594) of putting everything under `/config/tailscale` rather than directly in `/config`.

## Setup

1. Enter a root shell

    ```sh
    sudo bash
    ```

2. Create the required directories

    ```sh
    mkdir -p /config/firstboot.d /config/tailscale /config/tailscale/tailscaled.service.d
    ```

3. Fetch the `firstboot` script

    ```sh
    curl -o /config/firstboot.d/tailscale.sh https://raw.githubusercontent.com/jamesog/tailscale-edgeos/main/firstboot.d/tailscale.sh
    chmod 755 /config/firstboot.d/tailscale.sh
    ```

4. Download the latest MIPS release from https://pkgs.tailscale.com/stable/#static

    Different EdgeRouter models use either MIPS or MIPS-LE, so make sure you download the right tarball for your platform. <br>
    ER-4 is MIPS, ER-X is MIPSLE.

    ```sh
    curl https://pkgs.tailscale.com/stable/tailscale_X.Y.Z_mips.tgz | tar -zxvf - -C /tmp
    ```

6. Copy the extracted files to `/config/tailscale`

    ```sh
    cp -rv /tmp/tailscale_*/* /config/tailscale
    ```

7. Run the firstboot script and log in to Tailscale

    The example below enables subnet routing for one subnet, enables use as an exit node (Tailscale 1.6+), and uses a one-off pre-auth key, which can be generated at https://login.tailscale.com/admin/authkeys

    ```sh
    /config/firstboot.d/tailscale.sh
    tailscale up --advertise-routes 192.0.2.0/24 --advertise-exit-node --authkey tskey-XXX
    ```

8. (Optional) If you want `sshd` to explicitly listen on the Tailscale address instead of all addresses:

    1. Fetch the override unit

        ```sh
        curl -o /config/tailscale/tailscaled.service.d/before-ssh.conf https://raw.githubusercontent.com/jamesog/tailscale-edgeos/main/tailscaled.service.d/before-ssh.conf
        systemctl daemon-reload
        ```

    2. Exit the shell, enter configure mode and set the listen-address

        If you don't currently have any listen-address directives, make sure you add any other addresses you want to access the router by, such as a private network IP.

        N.B. the Tailscale IP can be found in the admin console, or using `tailscale status -peers=false | awk '{print $1}'`

        ```
        exit
        configure
        set service ssh listen-address <Tailscale IP>
        commit comment "sshd listen on Tailscale IP"
        ```

