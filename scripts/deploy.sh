#!/usr/bin/env bash
# Deploy (or re-deploy) the application with kubectl and wait until it serves
# requests end to end. Runs on the agent VM on every `vagrant up`, i.e. after
# both nodes are up.
set -euo pipefail
source /vagrant/scripts/lib.sh

KUBECTL=(k3s kubectl --kubeconfig "$CLUSTER_DIR/kubeconfig")
APP_URL="http://$SERVER_IP:30080"

show_state_on_failure() {
    log "Deployment did not become ready; current state:"
    "${KUBECTL[@]}" get nodes -o wide || true
    "${KUBECTL[@]}" -n hw3 get pods,services,pvc -o wide || true
    "${KUBECTL[@]}" -n hw3 get events --sort-by=.lastTimestamp | tail -20 || true
}
trap show_state_on_failure ERR

two_nodes_ready() {
    [[ $("${KUBECTL[@]}" get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l) -eq 2 ]]
}

log "Waiting for both nodes to be Ready"
wait_for 300 "two Ready nodes" two_nodes_ready
"${KUBECTL[@]}" get nodes -o wide

log "Applying manifests from k8s/"
"${KUBECTL[@]}" apply -f /vagrant/k8s/

# Pods keep running the old image when only the image contents changed under
# the same tag, so restart them after a rebuild.
images_sha=$(cat "$CLUSTER_DIR/images.sha")
deployed_sha=$("${KUBECTL[@]}" get namespace hw3 -o jsonpath='{.metadata.annotations.hw3/images-sha}')
if [[ -n "$deployed_sha" && "$deployed_sha" != "$images_sha" ]]; then
    log "Images changed ($deployed_sha -> $images_sha); restarting web and api"
    "${KUBECTL[@]}" -n hw3 rollout restart deployment/web deployment/api
fi
"${KUBECTL[@]}" annotate namespace hw3 --overwrite "hw3/images-sha=$images_sha" >/dev/null

log "Waiting for Deployments to become available"
"${KUBECTL[@]}" -n hw3 wait --for=condition=Available deployment --all --timeout=300s

# After a reboot the Deployments report Available before the restarted Pods
# actually serve traffic, so check the full Nginx -> Flask -> PostgreSQL path.
log "Waiting for $APP_URL/api/get_names to answer"
wait_for 300 "application at $APP_URL" curl -sf "$APP_URL/api/get_names"

"${KUBECTL[@]}" -n hw3 get pods,services,pvc -o wide
log "Application is ready: $APP_URL"
