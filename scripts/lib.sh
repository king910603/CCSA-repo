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

# K3s's unit uses KillMode=process, so stopping it leaves the containers
# running, and PostgreSQL was otherwise killed before it finished shutting
# down ("database system was not properly shut down" on the next boot). This
# unit is ordered before K3s, so on shutdown it stops after K3s (no kubelet
# left to restart containers) and sends SIGTERM to every container's main
# process, waiting up to 20s for them to exit.
install_shutdown_hook() {
    local k3s_service=$1

    cat > /usr/local/bin/hw3-stop-containers.sh <<'EOF'
#!/bin/sh
container_pids() {
    for shim in $(pgrep -f containerd-shim); do pgrep -P "$shim"; done
}
pids=$(container_pids)
[ -n "$pids" ] && kill -TERM $pids 2>/dev/null
for _ in $(seq 1 20); do
    [ -z "$(container_pids)" ] && break
    sleep 1
done
EOF
    chmod 755 /usr/local/bin/hw3-stop-containers.sh

    cat > /etc/systemd/system/hw3-stop-containers.service <<EOF
[Unit]
Description=Stop K3s containers cleanly before shutdown
Before=$k3s_service.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/local/bin/hw3-stop-containers.sh
TimeoutStopSec=45

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now hw3-stop-containers.service
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
