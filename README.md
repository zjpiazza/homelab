# homelab
Infrastructure as Code for my homelab.

## Secrets (SOPS + age)

Flux Kustomizations under `clusters/homelab/` decrypt secrets via the
`sops-age` Secret in the `flux-system` namespace.

### Applying / rotating the age key
The private age key is applied out-of-band (never committed). The form
below is idempotent — safe to rerun for initial setup or key rotation:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Encrypting a secret
Files matching `*.sops.yaml` are encrypted (see `.sops.yaml`):

```sh
sops --encrypt --in-place path/to/thing.sops.yaml
```

Edit later with `sops path/to/thing.sops.yaml`.

The repo's age recipient is
`age1swfkes9cealehclknyt350m8lj7faw3xwvnx3mllr28xeekq3vyqe8545h`.
