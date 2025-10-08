#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UNIT_SRC="$SCRIPT_DIR/systemd/squid-ssl-proxy.service"
UNIT_DST="/etc/systemd/system/squid-ssl-proxy.service"
CONF_SRC_DIR="$SCRIPT_DIR/config/conf.d"
CONF_DST_DIR="/etc/squid/conf.d"
TEMPLATE_SRC="$SCRIPT_DIR/config/squid.sample.conf"
TEMPLATE_DST="/etc/squid/squid.envsubst.conf"

if [[ ! -f "$UNIT_SRC" ]]; then
  echo "error: unit file not found at $UNIT_SRC" >&2
  exit 1
fi

echo "Installing systemd unit to $UNIT_DST" >&2
sudo install -m 0644 "$UNIT_SRC" "$UNIT_DST"

echo "Ensuring configuration directories" >&2
sudo install -d -m 0755 /etc/squid /etc/squid/ca /etc/squid/conf.d

if [[ -d "$CONF_SRC_DIR" ]]; then
  echo "Syncing conf.d snippets" >&2
  sudo rsync -av --delete "$CONF_SRC_DIR/" "$CONF_DST_DIR/"
fi

if [[ -f "$TEMPLATE_SRC" ]]; then
  echo "Installing squid.envsubst.conf" >&2
  sudo install -m 0644 "$TEMPLATE_SRC" "$TEMPLATE_DST"
fi

echo "Reloading systemd daemon" >&2
sudo systemctl daemon-reload

echo
echo "To enable and start the service, run:" >&2
echo "  sudo systemctl enable --now squid-ssl-proxy.service" >&2
echo
