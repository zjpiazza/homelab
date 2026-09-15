# Dolt on homelab

A standalone, shared Dolt SQL server. This deployment does not initialize,
import, or change any project's Beads database.

## Deployment

| Setting | Value |
| --- | --- |
| Kubernetes context | `admin@homelab` |
| Namespace / StatefulSet | `dolt` / `dolt` |
| Image | `dolthub/dolt-sql-server:2.2.0` |
| Tailnet endpoint | `dolt.tail0ebb20.ts.net:3306` |
| Tailnet IP at initial deployment | `100.93.220.10` (prefer DNS) |
| Administrator | `dolt-admin` |
| Storage | `dolt-data`, 10 GiB, `rook-ceph-block`, ReadWriteOnce |
| Credentials | `dolt-auth` Secret, encrypted in `auth.sops.yaml` |

The single-replica StatefulSet runs the official image. Its persistent volume
holds database files and Dolt's SQL user/privilege configuration. Keep replicas
at **one**: additional replicas do not create a replicated Dolt cluster.

The Tailscale operator exposes TCP 3306 using `loadBalancerClass: tailscale`,
with no NodePort allocation. Its existing `tag:homelab-k8s` permissions apply.
The NetworkPolicy admits database connections only from this service's
Tailscale proxy pods. Tailnet policy controls which devices can reach that
proxy; SQL authentication is also required. No public ingress is configured.
Tailscale encrypts the client-to-proxy connection; the proxy-to-Dolt connection
uses the cluster network.

This directory is included by `apps/base/kustomization.yaml`. The existing
Flux `apps` Kustomization handles SOPS decryption using `flux-system/sops-age`.
The initial installation was applied directly. Flux adopts and reconciles
these resources when this change merges into the homelab main branch.

The namespace and PVC have Flux pruning disabled to preserve storage during
GitOps removal. The Ceph StorageClass uses reclaim policy `Delete`: manually
deleting the PVC or namespace can still delete the underlying data. A PVC is
not a backup. **Scheduled/off-cluster backups are not configured by this
deployment.** Arrange full Dolt backups before moving important project data
onto the server.

## Connect

Connect the client machine to Tailscale. Retrieve the administrator password
through your cluster access (this command prints the password):

```sh
kubectl --context admin@homelab -n dolt get secret dolt-auth \
  -o jsonpath='{.data.admin-password}' | base64 --decode
```

Using a MySQL-compatible client, which prompts for the password:

```sh
mysql --host=dolt.tail0ebb20.ts.net --port=3306 \
  --user=dolt-admin --password
```

Or with the Dolt CLI, supply the password via `DOLT_CLI_PASSWORD` and run:

```sh
dolt --host dolt.tail0ebb20.ts.net --port 3306 \
  --user dolt-admin --no-tls sql
```

`--no-tls` refers to SQL-layer TLS; the connection to the proxy still travels
over the encrypted tailnet. The `root` account is restricted to localhost and
reserved for in-pod maintenance. Do not distribute the administrator password
to project agents: provision a database and scoped SQL account per project.

## Adding projects

Create a distinct database and user for each project. For example, run the
following SQL as the administrator, replacing the example names and password:

```sql
CREATE DATABASE example_project;
CREATE USER 'example_project'@'%' IDENTIFIED BY '<generated-password>';
GRANT ALL PRIVILEGES ON example_project.* TO 'example_project'@'%';
```

For Beads, select server mode and configure the server host, port `3306`,
project database, project user, and `BEADS_DOLT_PASSWORD` on each machine.
Migrate existing data using Beads' full database backup/restore guidance;
changing connection settings alone does not migrate the old database. Keep
the source database until issue counts and history have been verified.

Database connections provide shared live state. Dolt Git remotes remain a
separate replication/backup mechanism and require server-side remote
credentials if used. This deployment installs no GitHub keys or tokens.

## Operations

```sh
kubectl --context admin@homelab -n dolt get pods,pvc,svc
kubectl --context admin@homelab -n dolt logs statefulset/dolt --tail=100
kubectl --context admin@homelab -n dolt rollout restart statefulset/dolt
kubectl --context admin@homelab -n dolt rollout status statefulset/dolt
```

Initialization runs `init.sql` once per data volume. The image creates the
administrator from the Secret; the init script grants it provisioning rights.
Updating the Secret alone does **not** rotate an existing administrator's SQL
password: update the SQL account using `ALTER USER`, then update and re-encrypt
the Secret with SOPS, and restart the pod. Keep a working session open until
the new credentials are verified.

Use SQL connections for administration while Dolt runs. Do not run offline
Dolt operations against the live database files. Keep the server image pinned;
Beads currently recommends Dolt 2.2.0 due to regressions in 2.3.x.

## References

- [Official Dolt container and persistence configuration](https://www.dolthub.com/docs/introduction/installation/docker/)
- [Beads server mode, version pin, and database migration](https://beads.gascity.com/architecture/dolt)
- [Tailscale Kubernetes service exposure](https://tailscale.com/docs/kubernetes-operator/ingress/expose-workload-to-tailnet-l3)
