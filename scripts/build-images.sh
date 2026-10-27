#!/usr/bin/env bash
# Build the web and api images on the control-plane VM and export them as a
# tarball that every node imports into K3s's containerd. Runs on every
# `vagrant up` but only rebuilds when files under src/ changed.
set -euo pipefail
source /vagrant/scripts/lib.sh

TARBALL="$CLUSTER_DIR/hw3-images.tar"
HASH_FILE="$CLUSTER_DIR/images.sha"

source_hash=$(cd /vagrant && find src -type f -not -path '*/tests/*' -not -name '*.pyc' -print0 \
    | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)

if [[ -f "$TARBALL" && "$(cat "$HASH_FILE" 2>/dev/null)" == "$source_hash" ]]; then
    log "Images are up to date ($source_hash)"
else
    if ! command -v docker >/dev/null; then
        log "Installing Docker (used only to build images)"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq docker.io >/dev/null
    fi
    # Keep Docker from touching iptables so it cannot interfere with K3s
    # networking; builds use the host network instead of a Docker bridge.
    mkdir -p /etc/docker
    echo '{"iptables": false, "ip6tables": false, "bridge": "none"}' > /etc/docker/daemon.json
    systemctl restart docker

    log "Building images for source revision $source_hash"
    docker build --network host -t hw3-api:1.0 /vagrant/src/backend
    docker build --network host -t hw3-web:1.0 /vagrant/src/frontend
    docker save hw3-api:1.0 hw3-web:1.0 -o "$TARBALL.tmp"
    mv "$TARBALL.tmp" "$TARBALL"
    echo "$source_hash" > "$HASH_FILE"

    # Docker is not needed at runtime; free its memory for the cluster.
    systemctl disable --now docker.service docker.socket >/dev/null 2>&1 || true
fi

bash /vagrant/scripts/import-images.sh
