#!/usr/bin/env bash
# Install K3s in agent mode and join the control plane. Runs once.
set -euo pipefail
source /vagrant/scripts/lib.sh

IFACE=$(iface_for_ip "$NODE_IP")

if ! systemctl is-enabled --quiet k3s-agent 2>/dev/null; then
    log "Installing K3s $K3S_VERSION agent on $NODE_IP ($IFACE), joining $SERVER_IP"
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" K3S_TOKEN="$K3S_TOKEN" \
        K3S_URL="https://$SERVER_IP:6443" sh -s - agent \
        --node-ip "$NODE_IP" \
        --flannel-iface "$IFACE"
fi
install_shutdown_hook k3s-agent

wait_for 300 "k3s-agent service active" systemctl is-active --quiet k3s-agent
log "K3s agent is running"
