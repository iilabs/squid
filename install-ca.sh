#!/usr/bin/env bash
set -euo pipefail

CA_SRC=${1:-/etc/squid/ca/CA.pem}

if [[ ! -f "$CA_SRC" ]]; then
  echo "error: CA certificate not found at $CA_SRC" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "error: this script must be run as root" >&2
  exit 1
fi

# Detect distro family
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "warning: /etc/os-release missing; defaulting to update-ca-trust" >&2
  ID_LIKE="rhel fedora"
fi

install_ca_rhel() {
  local dest="/etc/pki/ca-trust/source/anchors/squid-ssl-proxy.pem"
  install -m 0644 "$CA_SRC" "$dest"
  update-ca-trust extract
  echo "installed CA at $dest (update-ca-trust extract)"
}

install_ca_debian() {
  local dest="/usr/local/share/ca-certificates/squid-ssl-proxy.crt"
  install -m 0644 "$CA_SRC" "$dest"
  update-ca-certificates
  echo "installed CA at $dest (update-ca-certificates)"
}

if [[ ${ID:-} == "debian" || ${ID:-} == "ubuntu" || ${ID_LIKE:-} =~ (debian) ]]; then
  install_ca_debian
elif [[ ${ID:-} == "fedora" || ${ID:-} == "rhel" || ${ID:-} == "centos" || ${ID_LIKE:-} =~ (rhel|fedora) ]]; then
  install_ca_rhel
else
  echo "warning: unrecognised distribution ($ID); attempting RHEL-style install" >&2
  install_ca_rhel
fi
