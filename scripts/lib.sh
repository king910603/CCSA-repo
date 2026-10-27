# Shared helpers for the provisioning scripts (sourced, not executed).

CLUSTER_DIR=/vagrant/.cluster

log() {
    echo "[$(hostname)] $*"
}

# Name of the interface that owns the given IPv4 address (the host-only NIC).
# VirtualBox gives every VM the same NAT address on the first NIC, so K3s must
# be told explicitly which interface carries node-to-node traffic.
iface_for_ip() {
    ip -o -4 addr show | awk -v ip="$1" '$4 ~ "^"ip"/" { print $2; exit }'
}

# Retry a command until it succeeds or the timeout (seconds) expires.
wait_for() {
    local timeout=$1 description=$2
    shift 2
    local deadline=$((SECONDS + timeout))
    until "$@" >/dev/null 2>&1; do
        if ((SECONDS >= deadline)); then
            log "Timed out after ${timeout}s waiting for: $description"
            return 1
        fi
        sleep 3
    done
}
