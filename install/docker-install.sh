#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
msg_ok "Installed Dependencies"

get_latest_release() {
  curl -sL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
PORTAINER_LATEST_VERSION=$(get_latest_release "portainer/portainer")
PORTAINER_AGENT_LATEST_VERSION=$(get_latest_release "portainer/agent")
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

msg_info "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
#echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -sSL https://get.docker.com)
cat <<EOF >/etc/docker/daemon.json
{
 "proxies": {
   "default": {
     "httpProxy": "http://rie-proxy.justice.gouv.fr:8080",
     "httpsProxy": "http://rie-proxy.justice.gouv.fr:8080",
     "noProxy": "127.0.0.1,localhost,*.dom*.justice.fr,*.drsp*.justice.fr,*.intranet.justice.fr,*.intranet.justice.gouv.fr,*.rie.gouv.fr,10.*,140.*,150.*,intranet.justice.gouv.fr"
   }
 }
}
EOF
cat <<EOF >/root/.docker/daemon.json
{
 "proxies": {
   "default": {
     "httpProxy": "http://rie-proxy.justice.gouv.fr:8080",
     "httpsProxy": "http://rie-proxy.justice.gouv.fr:8080",
     "noProxy": "127.0.0.1,localhost,*.dom*.justice.fr,*.drsp*.justice.fr,*.intranet.justice.fr,*.intranet.justice.gouv.fr,*.rie.gouv.fr,10.*,140.*,150.*,intranet.justice.gouv.fr"
   }
 }
}
EOF
systemctl stop docker
systemctl start docker
mkdir -p /etc/systemd/system/docker.service.d
cat <<EOF >/etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://rie-proxy.justice.gouv.fr:8080"
Environment="HTTPS_PROXY=http://rie-proxy.justice.gouv.fr:8080"
Environment="NO_PROXY=127.0.0.1,localhost,*.ac*.justice.fr;*.ac.justice.fr;*.ader.gouv.fr;*.ader.senat.fr;*.amalfi.fr,127.0.0.0/8,10.0.0.0/8"
EOF
systemctl daemon-reload
systemctl stop docker
systemctl start docker
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

read -r -p "Would you like to add Portainer? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Portainer $PORTAINER_LATEST_VERSION"
  docker volume create portainer_data >/dev/null
  $STD docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name=portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  msg_ok "Installed Portainer $PORTAINER_LATEST_VERSION"
else
  read -r -p "Would you like to add the Portainer Agent? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Portainer agent $PORTAINER_AGENT_LATEST_VERSION"
    $STD docker run -d \
      -p 9001:9001 \
      --name portainer_agent \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/lib/docker/volumes:/var/lib/docker/volumes \
      portainer/agent
    msg_ok "Installed Portainer Agent $PORTAINER_AGENT_LATEST_VERSION"
  fi
fi
read -r -p "Would you like to add Docker Compose? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p $DOCKER_CONFIG/cli-plugins
  curl -sSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
  chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
  msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
