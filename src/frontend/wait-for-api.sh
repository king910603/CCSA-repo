#!/bin/sh
# nginx resolves proxy_pass hosts once at startup. Right after the cluster
# boots, CoreDNS may not answer yet, so wait for the "api" Service record
# instead of letting nginx exit and the Pod go into a restart loop.
for attempt in $(seq 1 60); do
    if getent hosts api >/dev/null 2>&1; then
        exit 0
    fi
    echo "Waiting for DNS record of Service 'api' ($attempt/60)"
    sleep 2
done
echo "Service 'api' is still not resolvable; starting nginx anyway"
