#!/usr/bin/env bash
# Collect evidence for the HW3 verification requirements (Part C).
#
# Run inside the control-plane VM:
#   vagrant ssh k3s-server -c "bash /vagrant/scripts/verify.sh"                 # checks 1-4
#   vagrant ssh k3s-server -c "bash /vagrant/scripts/verify.sh restart-before"  # check 5, step 1
#   vagrant halt && vagrant up
#   vagrant ssh k3s-server -c "bash /vagrant/scripts/verify.sh restart-after"   # check 5, step 2
#
# Output is printed and saved under evidence/. KUBECTL, APP_URLS and
# EVIDENCE_DIR can be overridden to run against another cluster.
set -uo pipefail

read -r -a KUBECTL <<< "${KUBECTL:-k3s kubectl}"
read -r -a APP_URLS <<< "${APP_URLS:-http://192.168.56.10:30080 http://192.168.56.11:30080}"
APP_URL=${APP_URLS[0]}
EVIDENCE_DIR=${EVIDENCE_DIR:-/vagrant/evidence}
MARKER_FILE="$EVIDENCE_DIR/.restart-marker"

k() { "${KUBECTL[@]}" "$@"; }

section() { printf '\n===== %s =====\n' "$*"; }
run() {
    local shown="$*"
    printf '\n$ %s\n' "${shown/#k /kubectl }"
    "$@"
}
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; }

api() {
    local method=$1 path=$2 body=${3:-}
    if [[ -n "$body" ]]; then
        curl -s -X "$method" "$APP_URL$path" -H 'Content-Type: application/json' -d "$body"
    else
        curl -s -X "$method" "$APP_URL$path"
    fi
}

has_name() { api GET /api/get_names | grep -q "\"name\":\"$1\""; }

wait_for_app() {
    for _ in $(seq 1 60); do
        curl -sf "$APP_URL/api/get_names" >/dev/null && return 0
        sleep 3
    done
    return 1
}

db_pod() { k -n hw3 get pod -l app=db -o jsonpath='{.items[0].metadata.name}'; }

check_nodes() {
    section "1. Cluster startup: both nodes Ready"
    run k get nodes -o wide
    local ready
    ready=$(k get nodes --no-headers | awk '$2 == "Ready"' | wc -l)
    [[ $ready -eq 2 ]] && pass "2 of 2 nodes are Ready" || fail "$ready of 2 nodes are Ready"
    run k -n hw3 get deployments,pods,services,pvc -o wide
}

check_app() {
    section "2. Application functionality through the Nginx NodePort"
    local name="verify-$(date +%s)"
    for url in "${APP_URLS[@]}"; do
        printf '\n$ curl -s -o /dev/null -w "%%{http_code}" %s/\n' "$url"
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' "$url/")
        echo "$code"
        [[ $code == 200 ]] && pass "web UI served by NodePort at $url" || fail "web UI at $url returned $code"
    done

    printf '\n$ POST %s/api/add_name {"name":"%s"}\n' "$APP_URL" "$name"
    api POST /api/add_name "{\"name\":\"$name\"}"; echo
    printf '\n$ GET %s/api/get_names\n' "$APP_URL"
    api GET /api/get_names; echo
    has_name "$name" && pass "added name is returned by get_names" || fail "added name missing"

    printf '\n$ DELETE %s/api/remove_name {"name":"%s"}\n' "$APP_URL" "$name"
    api DELETE /api/remove_name "{\"name\":\"$name\"}"; echo
    has_name "$name" && fail "name still present after delete" || pass "deleted name is gone"

    printf '\n$ POST %s/api/add_name {"name":"   "}\n' "$APP_URL"
    local rejected
    rejected=$(api POST /api/add_name '{"name":"   "}')
    echo "$rejected"
    [[ $rejected == *'"error"'* ]] && pass "blank name is rejected" || fail "blank name was accepted"
}

check_connectivity() {
    section "3. Inter-tier connectivity through Kubernetes Services"
    run k -n hw3 get services,endpointslices -o wide
    run k -n hw3 exec deploy/web -- grep -n proxy_pass /etc/nginx/conf.d/default.conf

    printf '\n$ kubectl -n hw3 exec deploy/web -- wget -qO- http://api:5000/health\n'
    local health
    health=$(k -n hw3 exec deploy/web -- wget -qO- http://api:5000/health)
    echo "$health"
    [[ $health == *healthy* && $health != *unhealthy* ]] \
        && pass "Nginx Pod reaches Flask via Service 'api'" || fail "Nginx Pod cannot reach Flask"

    run k -n hw3 exec deploy/api -- printenv DB_HOST DB_PORT
    printf '\n$ kubectl -n hw3 exec deploy/api -- python (connect to host "db")\n'
    local result
    result=$(k -n hw3 exec deploy/api -- python -c '
import socket
from app import database_url_from_env, get_connection
print("Service db resolves to", socket.gethostbyname("db"))
with get_connection(database_url_from_env()) as c:
    print(c.execute("SELECT version()").fetchone()["version"])
    print("rows in names:", c.execute("SELECT count(*) AS n FROM names").fetchone()["n"])
')
    echo "$result"
    [[ $result == *PostgreSQL* ]] \
        && pass "Flask Pod queries PostgreSQL via Service 'db'" || fail "Flask Pod cannot query PostgreSQL"
}

check_persistence() {
    section "4. Data persistence across PostgreSQL Pod recreation"
    local name="persist-$(date +%s)" before after
    printf '\n$ POST %s/api/add_name {"name":"%s"}\n' "$APP_URL" "$name"
    api POST /api/add_name "{\"name\":\"$name\"}"; echo

    before=$(db_pod)
    run k -n hw3 get pod "$before" -o wide
    run k -n hw3 delete pod "$before"
    run k -n hw3 wait --for=condition=Ready pod -l app=db --timeout=180s
    after=$(db_pod)
    run k -n hw3 get pod "$after" -o wide
    [[ $before != "$after" ]] && pass "db Pod was recreated ($before -> $after)" || fail "db Pod was not recreated"

    wait_for_app
    printf '\n$ GET %s/api/get_names\n' "$APP_URL"
    api GET /api/get_names; echo
    has_name "$name" && pass "'$name' survived Pod recreation" || fail "'$name' was lost"
    run k get pv
}

restart_before() {
    section "5. Cluster restart (before vagrant halt)"
    local name="restart-$(date +%s)"
    check_nodes
    printf '\n$ POST %s/api/add_name {"name":"%s"}\n' "$APP_URL" "$name"
    api POST /api/add_name "{\"name\":\"$name\"}"; echo
    has_name "$name" && pass "stored '$name' before restart" || fail "could not store '$name'"
    echo "$name" > "$MARKER_FILE"
    echo
    echo "Next: run 'vagrant halt', then 'vagrant up', then 'verify.sh restart-after'."
}

restart_after() {
    section "5. Cluster restart (after vagrant halt + vagrant up)"
    local name
    name=$(cat "$MARKER_FILE" 2>/dev/null) || { fail "run 'verify.sh restart-before' first"; return; }
    run uptime
    check_nodes
    wait_for_app
    printf '\n$ GET %s/api/get_names\n' "$APP_URL"
    api GET /api/get_names; echo
    has_name "$name" && pass "'$name' stored before the restart is still present" || fail "'$name' was lost"
    check_app
}

# Run one check, show its output and save it as an evidence file.
WRITTEN=()
record() {
    local file="$EVIDENCE_DIR/$1"
    "$2" 2>&1 | tee "$file"
    WRITTEN+=("$file")
}

mode=${1:-all}
mkdir -p "$EVIDENCE_DIR"
case $mode in
    all)
        record 01-cluster-startup.txt check_nodes
        record 02-application.txt check_app
        record 03-connectivity.txt check_connectivity
        record 04-persistence.txt check_persistence
        ;;
    restart-before) record 05-restart-before.txt restart_before ;;
    restart-after) record 05-restart-after.txt restart_after ;;
    *) echo "usage: $0 [all|restart-before|restart-after]" >&2; exit 2 ;;
esac

# Checks run inside pipelines (subshells), so count failures from the output.
failed=$(cat "${WRITTEN[@]}" | grep -c '^FAIL:')
echo
echo "Evidence saved in $EVIDENCE_DIR: $failed failing check(s)"
[[ $failed -eq 0 ]]
