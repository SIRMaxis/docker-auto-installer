#!/usr/bin/env bash
set -euo pipefail

MIRROR_URL="https://docker.iw5.ir"
DAEMON_JSON_PATH="/etc/docker/daemon.json"

log() { echo -e "\n==> $*"; }
die() { echo -e "\n[ERROR] $*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root: sudo bash $0"
  fi
}

load_os_release() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  else
    die "/etc/os-release not found. Cannot detect distro."
  fi

  OS_ID="${ID:-unknown}"
  OS_ID_LIKE="${ID_LIKE:-}"
  OS_NAME="${NAME:-unknown}"
  OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
  OS_UBUNTU_CODENAME="${UBUNTU_CODENAME:-}"
}

is_like() {
  local needle="$1"
  [[ " ${OS_ID} ${OS_ID_LIKE} " =~ [[:space:]]${needle}[[:space:]] ]]
}

write_daemon_json() {
  log "Writing ${DAEMON_JSON_PATH}"
  mkdir -p /etc/docker
  cat > "${DAEMON_JSON_PATH}" <<EOF
{
  "insecure-registries": ["${MIRROR_URL}"],
  "registry-mirrors": ["${MIRROR_URL}"]
}
EOF
}

restart_docker() {
  log "Restarting Docker"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    # enable if available, but don't fail the script if enabling isn't supported
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl restart docker
  else
    # Fallback (older systems)
    service docker restart || die "Could not restart docker (no systemctl/service success)."
  fi
}

install_apt_based() {
  local repo_os="$1"   # ubuntu | debian | raspbian
  local codename

  codename="${OS_UBUNTU_CODENAME:-$OS_VERSION_CODENAME}"
  if [[ -z "${codename}" ]]; then
    die "Could not determine distro codename (VERSION_CODENAME/UBUNTU_CODENAME empty)."
  fi

  log "Detected APT-based distro: ${OS_NAME} (repo: ${repo_os}, codename: ${codename})"

  log "apt update + prerequisites"
  apt-get update
  apt-get install -y ca-certificates curl

  log "Adding Docker GPG key"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${repo_os}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  log "Adding Docker APT repository"
  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/${repo_os}
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  log "apt update"
  apt-get update

  log "Installing Docker Engine + plugins"
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_dnf_based() {
  local repo_os="$1"  # rhel | fedora | centos

  log "Detected RPM/DNF-based distro: ${OS_NAME} (repo: ${repo_os})"

  log "Installing DNF repo tooling"
  dnf -y install dnf-plugins-core

  log "Adding Docker RPM repository"
  # Docker docs differ slightly between Fedora vs others, but both forms are accepted on modern dnf.
  # We use the most widely supported form:
  dnf config-manager --add-repo "https://download.docker.com/linux/${repo_os}/docker-ce.repo"

  log "Installing Docker Engine + plugins"
  dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Starting Docker"
  systemctl enable --now docker || true
}

main() {
  require_root
  load_os_release

  log "OS detected: ${OS_NAME} (ID=${OS_ID} ID_LIKE=${OS_ID_LIKE})"

  # APT family
  if [[ "${OS_ID}" == "ubuntu" ]] || is_like ubuntu; then
    install_apt_based "ubuntu"
  elif [[ "${OS_ID}" == "debian" ]] || is_like debian; then
    # Raspberry Pi OS sometimes reports ID=raspbian, sometimes debian-like.
    if [[ "${OS_ID}" == "raspbian" ]] || is_like raspbian; then
      install_apt_based "raspbian"
    else
      install_apt_based "debian"
    fi
  elif [[ "${OS_ID}" == "raspbian" ]] || is_like raspbian; then
    install_apt_based "raspbian"

  # DNF family
  elif [[ "${OS_ID}" == "rhel" ]] || is_like rhel; then
    install_dnf_based "rhel"
  elif [[ "${OS_ID}" == "fedora" ]] || is_like fedora; then
    install_dnf_based "fedora"
  elif [[ "${OS_ID}" == "centos" ]] || is_like centos; then
    install_dnf_based "centos"
  else
    die "Unsupported distro: ${OS_NAME} (ID=${OS_ID}, ID_LIKE=${OS_ID_LIKE})"
  fi

  write_daemon_json
  restart_docker

  log "Done. Versions:"
  docker --version || true
  docker compose version || true
}

main "$@"
