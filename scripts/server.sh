#!/usr/bin/env bash
# Install and start the K3s control plane. Runs once, on first `vagrant up`.
set -euo pipefail
source /vagrant/scripts/lib.sh

IFACE=$(iface_for_ip "$NODE_IP")

if ! systemctl is-enabled --quiet k3s 2>/dev/null; then
    log "Installing K3s $K3S_VERSION server on $NODE_IP ($IFACE)"
    # Traefik is not used: the web tier is exposed through a NodePort Service.
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" K3S_TOKEN="$K3S_TOKEN" sh -s - server \
        --node-ip "$NODE_IP" \
        --advertise-address "$NODE_IP" \
        --flannel-iface "$IFACE" \
        --write-kubeconfig-mode 644 \
        --disable traefik
fi
install_shutdown_hook k3s

wait_for 300 "k3s-server node Ready" \
    sh -c "k3s kubectl get node k3s-server | grep -qw Ready"

# Kubeconfig usable from the agent VM and from the host.
mkdir -p "$CLUSTER_DIR"
sed "s/127.0.0.1/$NODE_IP/" /etc/rancher/k3s/k3s.yaml > "$CLUSTER_DIR/kubeconfig"
log "K3s server is Ready; kubeconfig written to .cluster/kubeconfig"
