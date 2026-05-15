# homelab
Infrastructure as Code for my homelab.

## Secrets (SOPS + age)

Flux Kustomizations under `clusters/homelab/` decrypt secrets via the
`sops-age` Secret in the `flux-system` namespace.

### One-time cluster setup
The private age key is applied out-of-band (never committed):

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
```

### Encrypting a secret
Files matching `*.sops.yaml` are encrypted (see `.sops.yaml`):

```sh
sops --encrypt --in-place path/to/thing.sops.yaml
```

Edit later with `sops path/to/thing.sops.yaml`.

The repo's age recipient is
`age1swfkes9cealehclknyt350m8lj7faw3xwvnx3mllr28xeekq3vyqe8545h`.
