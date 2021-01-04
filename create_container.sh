#!/usr/bin/env bash

# Setup script environment
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
 # [ ! -z ${CTID-} ] && cleanup_ctid
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

# Create LXC

#TODO add routine for skipping the launch and/or reinstalling

OSTYPE=images
OSVERSION=debian/buster
INSTANCENAME=homeassistant

lxc launch $OSTYPE:$OSVERSION $INSTANCENAME -c security.privileged=true -c security.nesting=true 

# Download setup script
# TODO: Is this really needed?
REPO="https://github.com/thiscantbeserious/lxd_homeassistant_install/"
wget -qO - ${REPO}/tarball/master | tar -xz --strip-components=1

# Modify LXC permissions to support Docker
alias lxc-set-config="lxc config set $INSTANCENAME"
cat <<'EOF' | lxc-set-config raw.lxc -
lxc.cgroup.devices.allow = a
lxc.cap.drop =
lxc.apparmor.profile=unconfined
lxc.mount.auto=proc:rw sys:rw
EOF

# Load modules for Docker before starting LXC
# Notice 03.01.2021: This is currently crashing Docker constantly so it's disabled for now.
# TODO: FIXME
#cat <<'EOF' | lxc-set-config raw.lxc -
#lxc.hook.pre-start = sh -ec 'for module in aufs overlay; do modinfo $module; $(lsmod | grep -Fq $module) || modprobe $module; done;'
#EOF

# Set container timezone to match host
# Notice 03.01.2021: Not sure if this is needed so leaving it here for now
#cat <<'EOF' | lxc-set-config raw.lxc -
#lxc.hook.mount = sh -c 'ln -fs $(readlink /etc/localtime) ${LXC_ROOTFS_MOUNT}/etc/localtime'
#EOF

# Setup container for Home Assistant
#msg "Starting LXC container..."
#lxc start $INSTANCENAME

### Begin LXC commands ###
alias lxc-cmd="lxc exec $INSTANCENAME -- "
# Prepare container OS
msg "Setting up container OS..."
lxc-cmd dhclient -4
lxc-cmd sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
lxc-cmd locale-gen >/dev/null
#Not sure why this was even done to begin with, TODO decide upon include or removal
#lxc-cmd apt-get remove -y openssh-{client,server} 2>/dev/null 
#lxc-cmd dpkg -r --force-depends openssh-{client,server} 2>/dev/null
# Update container OS
msg "Updating container OS..."
lxc-cmd apt-get update >/dev/null
lxc-cmd apt-get -qqy upgrade &>/dev/null

# Install prerequisites
msg "Installing prerequisites..."
lxc-cmd apt-get -qqy install \
    avahi-daemon curl jq network-manager xterm apparmor apparmor-utils &>/dev/null

# Install Docker
msg "Installing Docker..."
lxc-cmd /bin/bash -c "sh <(curl -sSL https://get.docker.com) &>/dev/null"

msg "Restarting LXC Container ..."
lxc restart $INSTANCENAME

sleep 5

msg "Executing homeassistant supervised-installer..."
lxc-cmd /bin/bash -c "curl -sSL https://raw.githubusercontent.com/home-assistant/supervised-installer/master/installer.sh | bash -s -- -m qemuarm-64"
    
sleep 5

msg "Adding proxy port for 8123..."
lxc config device add $INSTANCENAME web proxy listen=tcp:0.0.0.0:8123 connect=tcp:127.0.0.1:8123
 
# Show completion message
info "Successfully created Home Assistant LXC named $INSTANCENAME which is accessible on Port 8123 from your host."
