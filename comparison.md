# Docker Compose vs K3s

**Scope.** Docker Compose runs containers on one Docker host. K3s is a
lightweight Kubernetes distribution that schedules containers across several
nodes; here a control-plane VM and a worker VM form one cluster.

**Configuration.** HW2 used one `docker-compose.yml` with three services. HW3
needs separate objects for each concern: Deployments for the containers,
Services for addressing, a PersistentVolumeClaim for storage and a Secret for
credentials. This is more YAML, but each part can be changed on its own.

**Networking.** Compose puts services on a bridge network where the service
name is a DNS name on one host. Kubernetes Services provide a stable virtual IP
and DNS name that work from any node, so Nginx reaches `api` and Flask reaches
`db` wherever the Pods run. External access uses a NodePort instead of a host
port mapping.

**Storage.** A Compose named volume lives on the single Docker host. In K3s,
a PVC asks the `local-path` provisioner for a volume; it survives Pod
recreation, but the data stays on one node, so the database Pod is pinned to
that node.

**Startup and recovery.** Compose orders startup with `depends_on` and health
checks. Kubernetes does not order Deployments; each tier must tolerate missing
dependencies (Flask retries the database, Nginx waits for the `api` DNS
record) while readiness probes keep traffic away until a Pod is ready. In
return, a Deployment recreates a deleted or crashed Pod automatically.

**Images.** Compose builds images locally on demand. K3s nodes need the image
in their own containerd, so images are built once and imported on every node.

**Trade-off.** Compose is simpler for one machine and local development. K3s
adds setup cost but provides multi-node scheduling, self-healing and a path to
scaling and high availability.
