# Home Assistant install with LXD (Ubuntu Server 20.10)

[Forked from whiskerz007/proxmox_hassio_lxc](https://github.com/whiskerz007/proxmox_hassio_lxc). **The orginal script was aimed to be installed on Proxmox exclusively - this was modified for LXD on any Debian based Host OS**. It is currently being used on an **Ubuntu Server 20.10 aarch64 host on a RaspberryPi 4 8GB** executing the current upstream supervisor install with all dependencies, also exposing the port (8123) on the host.

TLDR: This is not aimed just at Proxmox but a generic debian based install (only tested on Ubuntu Server right now).

## Current state / how-to:

1. **Adjust MACHINE_TYPE manually** if you want to install it on x86_64 f.e. (it defaults to qemuarm-64, no prompt)
2. **select N upon install to keep network connectivity after reboot** (overwriting will remove eth0 and hence the internet connectivity) 

Maybe it's a better idea to rewrite HassOS Buildroot base to something like https://github.com/Linutronix/elbe to get a minimal Debian system as the base where you can properly install other packages in addition to Hass.io ...

## Known issues:

- DNS and Multicast are currently not working, [see this post in the forums](https://community.home-assistant.io/t/running-hassos-as-an-lxd-lxc-virtual-machine/227643/6?u=thiscantbeserious).

- Could be that there's a container restart policy issue.
    ```
    docker update --restart unless-stopped $(docker ps -q)
    ``` 
----

Original Readme - see here: https://github.com/whiskerz007/proxmox_hassio_lxc/blob/master/README.md
