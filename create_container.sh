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
OSTYPE=images
OSVERSION=debian/buster
INSTANCENAME=homeassistant

lxc launch $OSTYPE:$OSVERSION $INSTANCENAME -c security.privileged=true -c security.nesting=true 

# Download setup script
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
cat <<'EOF' | lxc-set-config raw.lxc -
lxc.hook.pre-start = sh -ec 'for module in aufs overlay; do modinfo $module; $(lsmod | grep -Fq $module) || modprobe $module; done;'
EOF

# Set container timezone to match host
#cat <<'EOF' | lxc-set-config raw.lxc -
#lxc.hook.mount = sh -c 'ln -fs $(readlink /etc/localtime) ${LXC_ROOTFS_MOUNT}/etc/localtime'
#EOF

# Setup container for Home Assistant
#msg "Starting LXC container..."
#pct start $CTID

### Begin LXC commands ###
alias lxc-cmd="lxc exec $INSTANCENAME -- "
# Prepare container OS
msg "Setting up container OS..."
lxc-cmd dhclient -4
lxc-cmd sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
lxc-cmd locale-gen >/dev/null
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

# Configure Docker configuration
#msg "Configuring Docker..."
#DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
#HA_URL_BASE=https://github.com/home-assistant/supervised-installer/raw/master/files
#lxc-cmd /bin/bash -c "mkdir -p $(dirname $DOCKER_CONFIG_PATH)"
#lxc-cmd /bin/bash -c "curl -sSLo $DOCKER_CONFIG_PATH ${HA_URL_BASE}/docker_daemon.json"
#lxc-cmd systemctl restart docker

# Configure NetworkManager
#msg "Configuring NetworkManager..."
#NETWORKMANAGER_CONFIG_PATH='/etc/NetworkManager/NetworkManager.conf'
#lxc-cmd /bin/bash -c "curl -sSLo $NETWORKMANAGER_CONFIG_PATH ${HA_URL_BASE}/NetworkManager.conf"
#lxc-cmd sed -i 's/type\:veth/interface-name\:veth\*/' $NETWORKMANAGER_CONFIG_PATH
#NETWORKMANAGER_PROFILE_PATH='/etc/NetworkManager/system-connections/default'
#lxc-cmd /bin/bash -c "curl -sSLo $NETWORKMANAGER_PROFILE_PATH ${HA_URL_BASE}/system-connection-default"
#lxc-cmd /bin/bash -c "chmod 600 $NETWORKMANAGER_PROFILE_PATH"
#NETWORKMANAGER_CONNECTION=$(lxc-cmd nmcli connection | grep eth0 | awk -F "  " '{print $1}')
#lxc-cmd nmcli connection down "$NETWORKMANAGER_CONNECTION" > /dev/null
#lxc-cmd nmcli connection delete "$NETWORKMANAGER_CONNECTION" > /dev/null
#lxc-cmd dhclient -r &> /dev/null
#lxc-cmd systemctl restart NetworkManager
#lxc-cmd nm-online -q

lxc restart $INSTANCENAME

sleep 5

lxc-cmd /bin/bash -c "curl -sSL https://raw.githubusercontent.com/home-assistant/supervised-installer/master/installer.sh | bash -s -- -m qemuarm-64"
    
sleep 5

lxc config device add $INSTANCENAME web proxy listen=tcp:0.0.0.0:8123 connect=tcp:127.0.0.1:8123
    
exit 0

# Create Home Assistant config
msg "Creating Home Assistant config..."
HASSIO_CONFIG_PATH=/etc/hassio.json
HASSIO_DOCKER=homeassistant/aarch64-hassio-supervisor
HASSIO_MACHINE=qemuarm-64
HASSIO_DATA_PATH=/usr/share/hassio
lxc-cmd /bin/bash -c "cat > $HASSIO_CONFIG_PATH <<- EOF
{
    \"supervisor\": \"${HASSIO_DOCKER}\",
    \"machine\": \"${HASSIO_MACHINE}\",
    \"data\": \"${HASSIO_DATA_PATH}\"
}
EOF
"

# Pull Home Assistant Supervisor image
msg "Downloading Home Assistant Supervisor container..."
HASSIO_VERSION=$(lxc-cmd bash -c "curl -s https://version.home-assistant.io/stable.json | jq -e -r '.supervisor'")
lxc-cmd docker pull "$HASSIO_DOCKER:$HASSIO_VERSION" > /dev/null
lxc-cmd docker tag "$HASSIO_DOCKER:$HASSIO_VERSION" "$HASSIO_DOCKER:latest" > /dev/null

# Install Home Assistant Supervisor
msg "Installing Home Assistant Supervisor..."
HASSIO_SUPERVISOR_PATH=/usr/sbin/hassio-supervisor
HASSIO_SUPERVISOR_SERVICE=/etc/systemd/system/hassio-supervisor.service
lxc-cmd bash -c "curl -sSLo $HASSIO_SUPERVISOR_PATH ${HA_URL_BASE}/hassio-supervisor"
lxc-cmd bash -c "chmod a+x $HASSIO_SUPERVISOR_PATH"
lxc-cmd bash -c "curl -sSLo $HASSIO_SUPERVISOR_SERVICE ${HA_URL_BASE}/hassio-supervisor.service"
lxc-cmd sed -i "s,%%HASSIO_CONFIG%%,${HASSIO_CONFIG_PATH},g" $HASSIO_SUPERVISOR_PATH
lxc-cmd sed -i -e "s,%%BINARY_DOCKER%%,/usr/bin/docker,g" \
  -e "s,%%SERVICE_DOCKER%%,docker.service,g" \
  -e "s,%%BINARY_HASSIO%%,${HASSIO_SUPERVISOR_PATH},g" \
  $HASSIO_SUPERVISOR_SERVICE
lxc-cmd systemctl enable hassio-supervisor.service > /dev/null 2>&1

# Create service to fix Home Assistant boot time check
#msg "Creating service to fix boot time check..."
#pct push $CTID hassio-fix-btime.service /etc/systemd/system/hassio-fix-btime.service
#lxc-cmd mkdir -p ${HASSIO_SUPERVISOR_SERVICE}.wants
#lxc-cmd ln -s /etc/systemd/system/{hassio-fix-btime.service,hassio-supervisor.service.wants/}

# Start Home Assistant Supervisor
msg "Starting Home Assistant..."
lxc-cmd systemctl start hassio-supervisor.service

# Install 'ha' cli
msg "Installing the 'ha' cli..."
lxc-cmd bash -c "curl -sSLo /usr/bin/ha ${HA_URL_BASE}/ha"
lxc-cmd bash -c "chmod a+x /usr/bin/ha"

# Setup 'ha' cli prompt
msg "Configuring 'ha' cli prompt..."
HA_CLI_PATH=/usr/sbin/hassio-cli
lxc-cmd bash -c "curl -sSLo $HA_CLI_PATH https://github.com/home-assistant/operating-system/raw/dev/buildroot-external/rootfs-overlay/usr/sbin/hassos-cli"
lxc-cmd sed -i 's,/bin/ash,/bin/bash,g' $HA_CLI_PATH
lxc-cmd sed -i '/# Run CLI container/,/^fi/d' $HA_CLI_PATH
lxc-cmd sed -i 's,^\(mesg n.*\)$,# \1,' /root/.profile
lxc-cmd chmod a+x $HA_CLI_PATH
lxc-cmd usermod --shell $HA_CLI_PATH root
lxc-cmd bash -c "echo -e '\ncd $HASSIO_DATA_PATH' >> /root/.bashrc"

# Cleanup container
msg "Cleanup..."
lxc-cmd apt-get autoremove >/dev/null
lxc-cmd apt-get autoclean >/dev/null
lxc-cmd rm -rf /var/{cache,log}/* /var/lib/apt/lists/*
### Finish LXC commands ###

# Get network details
#IP=$(pct exec $CTID ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')

# Show completion message
info "Successfully created Home Assistant LXC named $INSTANCENAME."
