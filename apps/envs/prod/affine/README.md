# AFFiNE

Self-hosted [AFFiNE](https://affine.pro) exposed at
`https://affine.wastelandsystems.io` via Cloudflare Tunnel.

## Topology

```
internet ──► Cloudflare ──► cloudflared (cluster-wide, runs in
                             cloudflare-operator-system)
                              └─► Service/affine:3010 ──► Deployment/affine
                                                            ├─► CNPG Cluster/affine-pg (pgvector)
                                                            ├─► StatefulSet/affine-redis
                                                            ├─► PVC/affine-storage  (initial blob storage)
                                                            └─► PVC/affine-config
```

The Cloudflare tunnel itself (`ClusterTunnel/wastelandsystems`) is shared
platform infrastructure — see
`infrastructure/controllers/cloudflare-operator/clustertunnel-wastelandsystems.yaml`.
This overlay only contributes a namespaced `TunnelBinding` that publishes
`affine.wastelandsystems.io` through it.

Blob storage starts on a PVC; after first admin login the storage backend
is switched to the Rook-Ceph S3 bucket provisioned by `obc.yaml` (see
"Switch to S3 storage" below).

## Repo layout

- `apps/base/affine/` – environment-agnostic manifests (namespace, CNPG,
  Redis, Deployment, migration Job, Services, PVCs).
- `apps/envs/prod/affine/` – prod overlay: ObjectBucketClaim, server URL
  ConfigMap, TunnelBinding for `affine.wastelandsystems.io`.
- `clusters/homelab/flux-system/affine-kustomization.yaml` – Flux entrypoint.

## First-time deploy

1. **Make sure the cluster-wide `wastelandsystems` ClusterTunnel is healthy.**
   It's defined in
   `infrastructure/controllers/cloudflare-operator/clustertunnel-wastelandsystems.yaml`
   and uses the existing
   `cloudflare-operator-system/cloudflare-secrets` Secret. The API token in
   that Secret must have **Zone ▸ DNS ▸ Edit** on the `wastelandsystems.io`
   zone in addition to whatever zones it already covers (e.g.
   `homeharbor.cloud`). If it doesn't, re-issue the token in the Cloudflare
   dashboard and update the SOPS file:

   ```sh
   sops infrastructure/controllers/cloudflare-operator/cloudflare-secrets.sops.yaml
   ```

   Verify:

   ```sh
   kubectl get clustertunnel wastelandsystems -o wide
   kubectl -n cloudflare-operator-system get pods -l tunnels.networking.cfargotunnel.com/cr=wastelandsystems
   ```

2. **Commit & push.** Flux picks up
   `clusters/homelab/flux-system/affine-kustomization.yaml` and reconciles
   `./apps/envs/prod/affine`.

   ```sh
   flux reconcile kustomization affine --with-source
   kubectl -n affine get pods,svc,pvc,objectbucketclaim,tunnelbinding
   ```

3. **Sign up the first user.** The first account to register via
   `https://affine.wastelandsystems.io/admin` becomes the instance admin.

## Switch to S3 storage

Once AFFiNE is up and you've signed in as admin:

1. Pull the OBC-generated credentials and endpoint:

   ```sh
   kubectl -n affine get cm affine-blobs \
     -o jsonpath='{"host="}{.data.BUCKET_HOST}{"\nport="}{.data.BUCKET_PORT}{"\nbucket="}{.data.BUCKET_NAME}{"\nregion="}{.data.BUCKET_REGION}{"\n"}'
   kubectl -n affine get secret affine-blobs \
     -o jsonpath='{"access_key="}{.data.AWS_ACCESS_KEY_ID}{"\nsecret_key="}{.data.AWS_SECRET_ACCESS_KEY}{"\n"}' \
     | while IFS== read k v; do printf '%s=%s\n' "$k" "$(echo "$v" | base64 -d)"; done
   ```

   `BUCKET_HOST` will be the in-cluster RGW Service
   (`rook-ceph-rgw-ceph-objectstore.rook-ceph.svc`).

2. Open `https://affine.wastelandsystems.io/admin` ▸ **Settings** ▸
   **Storage**. Switch provider to `aws-s3` and paste:

   ```json
   {
     "endpoint": "http://<BUCKET_HOST>:<BUCKET_PORT>",
     "region": "<BUCKET_REGION>",
     "bucket": "<BUCKET_NAME>",
     "credentials": {
       "accessKeyId": "<AWS_ACCESS_KEY_ID>",
       "secretAccessKey": "<AWS_SECRET_ACCESS_KEY>"
     },
     "forcePathStyle": true
   }
   ```

   `forcePathStyle: true` is required for Rook-Ceph RGW. Existing blobs on
   the `affine-storage` PVC are not migrated automatically — anything
   uploaded before the switch stays on the PVC.

## Operations

**Re-run database migrations** (e.g. after image upgrade):

```sh
kubectl -n affine delete job affine-migration --ignore-not-found
kubectl -n affine apply -k apps/envs/prod/affine
# or bump apps/base/affine/migration-job.yaml's migration-revision annotation
```

The pod Deployment also re-runs the migration as an initContainer on every
pod start, so the standalone Job is mainly useful for one-off CLI invocation.

**Bump AFFiNE version**: edit the `ghcr.io/toeverything/affine:stable` tag in
both `apps/base/affine/deployment.yaml` and
`apps/base/affine/migration-job.yaml`.

## Why these choices

- **`postgresql:16-standard-bookworm`** – ships pgvector, which AFFiNE
  requires when AI/embedding features are enabled and recommends in
  general. Avoids forking a Postgres image.
- **Single replica + `Recreate` strategy** – AFFiNE's self-hosted topology
  expects one server process for Yjs sync.
- **PVC blob storage first, S3 second** – S3 in AFFiNE is configured
  through the Admin Panel (not env vars), so the bucket has to exist first
  but can't be wired in declaratively. The PVC keeps day-0 functional.
- **`ClusterTunnel` instead of namespaced `Tunnel`** – `wastelandsystems.io`
  is shared across multiple internal apps. One cluster-wide tunnel + one
  cloudflared Deployment + one API token, with each app contributing only a
  namespaced `TunnelBinding`.
