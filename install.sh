#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

if [[ "${1-""}" == "" ]]; then
  echo "[ERROR] Please provide domain name as a first argument" >&2
  exit 1
fi

if [[ "${2-""}" == "" ]]; then
  echo "[ERROR] Please provide your frontend node key as a second argument" >&2
  exit 1
fi

cd "$(dirname "$0")"

SERVER_IP=$(hostname -I | awk '{ print $1 }')
NGINX_DOMAIN_CONF_URL="https://raw.githubusercontent.com/optriment/optrispace-frontend-node-installer/master/assets/nginx_domain.conf"

install_package() {
  local package_name="${1:?}"
  if ! dpkg -s "${package_name}" > /dev/null; then
    echo "[INFO] Installing ${package_name}..."
    apt-get install -y "${package_name}"
  fi
}

install_essentials() {
  install_package ca-certificates
  install_package curl
  install_package gnupg
  install_package lsb-release
  install_package dnsutils
  install_package git
  install_package socat
}

check_domain() {
  local domain_name="${1}"

  if ! dig -t A "${domain_name}" | grep "^${domain_name}" > /dev/null; then
    echo "[ERROR] Unable to find A record for domain ${domain_name} in DNS" >&2
    exit 1
  fi

  a_record_ip=$(dig -t A "${domain_name}" | grep "^${domain_name}" | awk '{ print $5 }')

  local a_record_set_to=${a_record_ip}

  if ! ip a | grep "${a_record_set_to}" > /dev/null; then
    echo "[ERROR] A record found in DNS, but value is set to ${a_record_set_to} instead of current server IP ${SERVER_IP}" >&2
    exit 1
  fi
}

install_docker() {
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    echo "[INFO] Downloading Docker GPG..."

    mkdir -p /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "[INFO] Adding Docker repository to apt...";

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
  fi

  install_package docker-ce
  install_package docker-ce-cli
  install_package containerd.io
  install_package docker-compose-plugin
}

install_nginx() {
  install_package nginx

  if [ ! -f /etc/nginx/ssl/dhparam.pem ]; then
    echo "[INFO] Generating dhparam for nginx..."

    mkdir -p /etc/nginx/ssl

    openssl dhparam -out /etc/nginx/ssl/dhparam.pem 4096
  fi
}

install_acme_sh() {
  local domain_name="${1:?}"

  if [ ! -d /root/acme.sh ]; then
    echo "[INFO] Cloning acme.sh..."

    git clone https://github.com/acmesh-official/acme.sh.git
  fi

  if [ ! -d /root/.acme.sh ]; then
    echo "[INFO] Installing acme.sh..."

    cd ~/acme.sh
    ./acme.sh --install -m "root@${domain_name}"
  fi
}

issue_ssl_certificate() {
  local domain_name="${1:?}"

  if [ -d "/root/.acme.sh/${domain_name}_ecc" ]; then
    return
  fi

  echo "[INFO] Requesting SSL certificate for ${domain_name}..."

  cd ~/.acme.sh
  ./acme.sh --issue -d "${domain_name}" -w /var/www/html
}

install_nginx_config() {
  local domain_name="${1:?}"
  local local_config_path="${HOME}/nginx_domain.conf"

  if [ -f "/etc/nginx/sites-enabled/${domain_name}.conf" ]; then
    return
  fi

  if [ ! -f "${local_config_path}" ]; then
    if ! curl --silent -o "${local_config_path}" "${NGINX_DOMAIN_CONF_URL}"; then
      echo "[ERROR] Unable to download ${NGINX_DOMAIN_CONF_URL}" >&2
      exit 1
    fi
  fi

  echo "[INFO] Installing nginx config for ${domain_name}..."

  sed "s/DOMAIN_NAME/${domain_name}/g" "${local_config_path}" > /etc/nginx/sites-enabled/"${domain_name}".conf
}

restart_nginx() {
  if ! nginx -t; then
    echo "[ERROR] Nginx config is not valid" >&2
    exit 1
  fi

  echo "[INFO] Restarting nginx..."

  systemctl restart nginx
}

add_local_user() {
  local username="${1:?}"

  if grep "${username}" /etc/passwd > /dev/null; then
    return
  fi

  echo "[INFO] Adding user ${username}..."

  useradd -m -s /bin/bash "${username}"
}

allow_sudo_for_user() {
  local username="${1:?}"

  if [ -f /etc/sudoers.d/"${username}" ]; then
    return
  fi

  echo "[INFO] Adding sudo rules..."

  echo "\"${username}\" ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/"${username}"
}

allow_docker_for_user() {
  local username="${1:?}"

  if groups "${username}" | grep docker > /dev/null; then
    return
  fi

  echo "[INFO] Adding ${username} to docker group..."

  usermod -a -G docker "${username}"
}

generate_ssh_keys_for_user() {
  local username="${1:?}"
  local domain_name="${2:?}"

  if [ -d /home/"${username}"/.ssh ]; then
    return
  fi

  echo "[INFO] Generating SSH keys..."

  runuser \
    -l "${username}" \
    -c "ssh-keygen -t rsa -b 4096 -N \"\" -C \"${username}@${domain_name}\" -f ~/.ssh/id_rsa"
}

configure_git_for_user() {
  local username="${1:?}"
  local domain_name="${2:?}"

  if ! runuser -l "${username}" -c "git config --global user.email" > /dev/null; then
    echo "[INFO] Adding user.email to git config"

    runuser -l "${username}" -c "git config --global user.email \"${username}@${domain_name}\""
  fi

  if ! runuser -l "${username}" -c "git config --global user.name" > /dev/null; then
    echo "[INFO] Adding user.name to git config"

    runuser -l "${username}" -c "git config --global user.name \"${username}\""
  fi
}

clone_frontend_repo_to_user() {
  local username="${1:?}"
  local frontend_repo="${2:?}"

  if [ -d "/home/${username}/frontend" ]; then
    return
  fi

  echo "[INFO] Cloning frontend repo..."

  runuser -l "${username}" -c "git clone ${frontend_repo} frontend"
}

configure_frontend_repo() {
  local username="${1:?}"
  local domain_name="${2:?}"
  local blockchain_network_id="${3:?}"
  local blockchain_view_address_url="${4:?}"
  local optrispace_contract_address="${5:?}"
  local frontend_node_key="${6:?}"

  local env_path="/home/${username}/frontend/.env.local"

  if [ -f "${env_path}" ]; then
    return
  fi

  echo "[INFO] Configuring frontend repo..."

  runuser -l "${username}" -c "touch ${env_path}"
  runuser -l "${username}" -c "echo \"DOMAIN=${domain_name}\" >> ${env_path}"
  runuser -l "${username}" -c "echo \"BLOCKCHAIN_NETWORK_ID=${blockchain_network_id}\" >> ${env_path}"
  runuser -l "${username}" -c "echo \"BLOCKCHAIN_VIEW_ADDRESS_URL=${blockchain_view_address_url}\" >> ${env_path}"
  runuser -l "${username}" -c "echo \"OPTRISPACE_CONTRACT_ADDRESS=${optrispace_contract_address}\" >> ${env_path}"
  runuser -l "${username}" -c "echo \"FRONTEND_NODE_ADDRESS=${frontend_node_key}\" >> ${env_path}"
}

build_docker_image() {
  local username="${1:?}"

  if docker images | grep frontend > /dev/null; then
    return
  fi

  echo "[INFO] Building Docker image..."

  runuser -l "${username}" -c "cd frontend && make build"
}

start_docker_container() {
  local username="${1:?}"

  if docker ps | grep frontend > /dev/null; then
    return
  fi

  echo "[INFO] Starting Docker container..."

  runuser -l "${username}" -c "cd frontend && make start"
}

main() {
  local domain_name="${1}"
  local frontend_node_key="${2}"
  local username="deploy"
  local frontend_repo="https://github.com/optriment/optrispace-frontend-v2.git"
  local blockchain_network_id="56"
  local blockchain_view_address_url="https://bscscan.com/address"
  local optrispace_contract_address="0x0a574c6f4D15795c322a636C69f4a2dc95b72C97"

  apt-get update
  apt-get upgrade

  install_essentials

  check_domain "${domain_name}"

  install_docker
  install_nginx
  install_acme_sh "${domain_name}"
  issue_ssl_certificate "${domain_name}"
  install_nginx_config "${domain_name}"

  add_local_user "${username}"
  allow_sudo_for_user "${username}"
  allow_docker_for_user "${username}"
  generate_ssh_keys_for_user "${username}" "${domain_name}"
  configure_git_for_user "${username}" "${domain_name}"

  clone_frontend_repo_to_user "${username}" "${frontend_repo}"
  configure_frontend_repo \
    "${username}" \
    "${domain_name}" \
    "${blockchain_network_id}" \
    "${blockchain_view_address_url}" \
    "${optrispace_contract_address}" \
    "${frontend_node_key}"

  build_docker_image "${username}"
  start_docker_container "${username}"

  restart_nginx
}

main "$@"
