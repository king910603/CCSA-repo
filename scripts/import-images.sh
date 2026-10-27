#!/usr/bin/env bash
# Import the application images into this node's K3s containerd so Pods with
# imagePullPolicy: Never can start here. Skips the import when this node
# already has the current build.
set -euo pipefail
source /vagrant/scripts/lib.sh

TARBALL="$CLUSTER_DIR/hw3-images.tar"
HASH_FILE="$CLUSTER_DIR/images.sha"
STAMP=/var/lib/hw3/images.sha

if [[ ! -f "$TARBALL" ]]; then
    log "No image tarball found; run 'vagrant provision k3s-server --provision-with images'"
    exit 1
fi

wait_for 180 "K3s containerd" k3s ctr version

wanted=$(cat "$HASH_FILE")
if [[ "$(cat "$STAMP" 2>/dev/null)" == "$wanted" ]] && \
        k3s ctr images ls -q | grep -q 'hw3-api:1.0' && \
        k3s ctr images ls -q | grep -q 'hw3-web:1.0'; then
    log "Images already imported ($wanted)"
    exit 0
fi

log "Importing images ($wanted) into K3s containerd"
k3s ctr images import "$TARBALL"
mkdir -p "$(dirname "$STAMP")"
echo "$wanted" > "$STAMP"
