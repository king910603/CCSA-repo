# HW3 — Three-Tier Web Application on a Two-Node K3s Cluster

The HW2 name-list application (Nginx → Flask → database) migrated from Docker
Compose to a two-node K3s cluster, with PostgreSQL replacing SQLite. One
command, `vagrant up`, creates both VMs, installs K3s, joins the worker,
builds the images and deploys the application with `kubectl`.

| Tier | Deployment | Service | Image |
|---|---|---|---|
| Web | `web` (1 replica) | `web` — **NodePort 30080** | `hw3-web:1.0` (Nginx, built from `src/frontend`) |
| Application | `api` (1 replica) | `api` — ClusterIP :5000 | `hw3-api:1.0` (Flask + Gunicorn, built from `src/backend`) |
| Database | `db` (1 replica) | `db` — ClusterIP :5432 | `postgres:17-alpine`, data on PVC `db-data` (`local-path`) |

See [architecture.pdf](architecture.pdf) for the diagram.

**Application URL:** <http://192.168.56.10:30080> (the NodePort also answers on <http://192.168.56.11:30080>)

## Prerequisites

| Requirement | Notes |
|---|---|
| [VirtualBox](https://www.virtualbox.org/wiki/Downloads) 7.1 or newer | 7.2+ for ARM64 hosts (Apple Silicon, Windows on ARM) |
| [Vagrant](https://developer.hashicorp.com/vagrant/install) 2.4 or newer | Needed for per-architecture boxes |
| ~4 GB free RAM, ~10 GB disk | Each VM gets 2 vCPU / 2 GB RAM |
| Internet access | K3s installer, Ubuntu packages, Docker Hub, PyPI (first `vagrant up` only, plus Docker Hub for `postgres`) |
| Host-only network 192.168.56.0/24 | VirtualBox's default allowed range; no change needed on a default install |

No other software is needed on the host. Docker is installed *inside* the
control-plane VM only to build the two application images.

The box is `bento/ubuntu-24.04`. The Vagrantfile picks the arm64 build on
Windows-on-ARM hosts and lets Vagrant auto-detect elsewhere; set
`HW3_BOX_ARCH=amd64` or `HW3_BOX_ARCH=arm64` to override.

## One-command lifecycle

Run all commands from this directory.

| Action | Command | What happens |
|---|---|---|
| **Start** | `vagrant up` | Creates/boots `k3s-server` then `k3s-agent`, installs K3s on first run, deploys the app and waits until it answers on the NodePort. First run ≈ 10–15 min, later boots ≈ 2–3 min. |
| **Stop** | `vagrant halt` | Shuts down both VMs. K3s, the images and the PostgreSQL data stay on the VM disks. |
| **Restart** | `vagrant up` | Boots both VMs; K3s starts from systemd and the deploy step re-applies `k8s/` and waits for the app again. No manual reconfiguration. |
| **Remove** | `vagrant destroy -f` | Deletes both VMs **and all database data**. |

`vagrant up` ends with output like:

```text
k3s-agent: NAME         STATUS   ROLES                  ...   INTERNAL-IP
k3s-agent: k3s-agent    Ready    <none>                 ...   192.168.56.11
k3s-agent: k3s-server   Ready    control-plane,master   ...   192.168.56.10
...
k3s-agent: [k3s-agent] Application is ready: http://192.168.56.10:30080
```

## What `vagrant up` does

| Step | Runs on | Script | When |
|---|---|---|---|
| 1. Install K3s server (pinned `v1.33.13+k3s1`, Traefik disabled, node IP on the host-only NIC) and export a kubeconfig to `.cluster/kubeconfig` | k3s-server | [scripts/server.sh](scripts/server.sh) | first boot |
| 2. Build `hw3-web:1.0` and `hw3-api:1.0` with Docker, save them to `.cluster/hw3-images.tar`, import them into K3s's containerd | k3s-server | [scripts/build-images.sh](scripts/build-images.sh) | every boot; rebuilds only if `src/` changed |
| 3. Install K3s agent and join `https://192.168.56.10:6443` with the shared token | k3s-agent | [scripts/agent.sh](scripts/agent.sh) | first boot |
| 4. Import the images into the agent's containerd | k3s-agent | [scripts/import-images.sh](scripts/import-images.sh) | every boot; skipped if current |
| 5. Wait for 2 Ready nodes, `kubectl apply -f k8s/`, wait for the Deployments and for `GET /api/get_names` through the NodePort | k3s-agent | [scripts/deploy.sh](scripts/deploy.sh) | every boot |

The pods use `imagePullPolicy: Never`, so the application images never need a
registry. The join token is generated once into `.cluster/node-token`.

## Kubernetes resources (`k8s/`)

Applied in file-name order by `kubectl apply -f k8s/`:

| File | Resources |
|---|---|
| [00-namespace.yaml](k8s/00-namespace.yaml) | Namespace `hw3` |
| [10-db-secret.yaml](k8s/10-db-secret.yaml) | Secret `db-credentials` (demo credentials) |
| [11-db-pvc.yaml](k8s/11-db-pvc.yaml) | PVC `db-data`: `local-path`, ReadWriteOnce, 1Gi |
| [20-db.yaml](k8s/20-db.yaml) | Deployment `db` (strategy `Recreate`, PVC at `/var/lib/postgresql/data`, pinned to `k3s-agent`) + ClusterIP Service `db` |
| [30-api.yaml](k8s/30-api.yaml) | Deployment `api` (`DB_HOST=db`, credentials from the Secret) + ClusterIP Service `api` |
| [40-web.yaml](k8s/40-web.yaml) | Deployment `web` + NodePort Service `web` (30080 → 80) |

Tiers find each other only by Service name: Nginx proxies `/api/` to
`http://api:5000`, and Flask connects to host `db` on port 5432.

The `db` Deployment is pinned to `k3s-agent` because a `local-path` volume
exists only on the node where it was first created; `Recreate` guarantees two
PostgreSQL processes never share the data directory.

## Using kubectl

Inside the control-plane VM:

```bash
vagrant ssh k3s-server -c "kubectl get nodes -o wide"
vagrant ssh k3s-server -c "kubectl -n hw3 get pods,svc,pvc -o wide"
```

Or from the host, if kubectl is installed there:

```bash
kubectl --kubeconfig .cluster/kubeconfig -n hw3 get pods -o wide
```

## Verification (Part C)

[scripts/verify.sh](scripts/verify.sh) runs the checks inside the control-plane
VM and saves the output under [evidence/](evidence/).

```bash
# 1-4: nodes Ready, app via NodePort, inter-tier Services, persistence after db Pod deletion
vagrant ssh k3s-server -c "bash /vagrant/scripts/verify.sh"

# 5: cluster restart
vagrant ssh k3s-server -c "bash /vagrant/scripts/verify.sh restart-before"
vagrant halt
vagrant up
vagrant ssh k3s-server -c "bash /vagrant/scripts/verify.sh restart-after"
```

| Requirement | Evidence file | How it is checked |
|---|---|---|
| 1. Cluster startup | `01-cluster-startup.txt` | `kubectl get nodes`: 2/2 Ready; all Deployments/Pods/PVC listed |
| 2. Application functionality | `02-application.txt` | UI on both node IPs at :30080; add → list → delete → list via `/api/*`; blank name rejected |
| 3. Inter-tier connectivity | `03-connectivity.txt` | `web` Pod calls `http://api:5000/health`; `api` Pod connects to `db` and runs SQL |
| 4. Data persistence | `04-persistence.txt` | add a record, delete the `db` Pod, record is returned by the new Pod |
| 5. Cluster restart | `05-restart-before.txt`, `05-restart-after.txt` | record stored before `vagrant halt` is present after `vagrant up`; full add/list/delete works |

Manual browser check: open <http://192.168.56.10:30080>, add a name, select
**Get names**, delete it, and select **Get names** again.

## Updating the application code

After changing files in `src/`, rebuild and redeploy without recreating the VMs:

```bash
vagrant provision k3s-server --provision-with images
vagrant provision k3s-agent --provision-with images,deploy
```

`deploy.sh` restarts the `web` and `api` Deployments when the image contents changed.

## API

| Method & path | Body | Result |
|---|---|---|
| `POST /api/add_name` | `{"name": "Alice"}` | `201` with the new row |
| `GET /api/get_names` | — | `{"names": [{"id", "name", "created_at"}]}` |
| `DELETE /api/remove_name` | `{"id": 1}` or `{"name": "Alice"}` | removes one row (first match by name) |
| `GET /health` | — | `200` when PostgreSQL is reachable (readiness probe) |

Names must be 1–100 non-blank characters.

## Backend tests

The tests need a PostgreSQL server:

```bash
docker run --rm -d --name hw3-test-pg -p 5432:5432 -e POSTGRES_PASSWORD=test postgres:17-alpine
cd src/backend
python -m pip install -r requirements-dev.txt
TEST_DATABASE_URL=postgresql://postgres:test@localhost:5432/postgres python -m pytest
```

## Repository layout

```text
.
├── README.md            this file
├── Vagrantfile          two VMs: k3s-server (192.168.56.10), k3s-agent (192.168.56.11)
├── architecture.pdf     one-page architecture diagram (source: docs/architecture.html)
├── comparison.md        Docker Compose vs K3s
├── scripts/             provisioning, deployment and verification scripts
├── k8s/                 Kubernetes manifests
├── src/
│   ├── frontend/        Nginx config, static UI, Dockerfile
│   └── backend/         Flask app, tests, Dockerfile
└── evidence/            output of scripts/verify.sh
```

## Packaging the submission

```bash
git archive --format=zip -o HW3_<StudentID>.zip HEAD README.md Vagrantfile architecture.pdf comparison.md scripts k8s src evidence
```

## Troubleshooting

- **`vagrant up` fails with a host-only network error:** another VirtualBox
  network already uses 192.168.56.0/24 differently; edit `SERVER_IP` and
  `AGENT_IP` in the Vagrantfile.
- **VirtualBox is slow or fails to start VMs on Windows:** Hyper-V-based
  features (WSL 2, Docker Desktop, Memory Integrity) force VirtualBox onto
  the slower Hyper-V backend; disabling them speeds up provisioning.
- **The app is not reachable after `vagrant up`:** the deploy step prints the
  Pod status on failure; rerun it with `vagrant provision k3s-agent --provision-with deploy`.
