# Homelab Backlog

## ✅ Completed

- [x] 3-node Talos HA control plane (nova, orbit, comet)
- [x] PXE boot server on atlas (dnsmasq + TFTP + HTTP)
- [x] Fresh iPXE build with embedded boot script
- [x] Cluster VIP (192.168.1.240)
- [x] UPS detected and NUT installed (CyberPower CP1500PFCRM2U)
- [x] Flux v2 bootstrapped from GitHub

## Rack/Hardware

- [ ] Cable management and labeling
- [ ] Document IP assignments and hardware specs
- [ ] Set up remote management (iKVM/IPMI if available)
- [ ] Configure UPS graceful shutdown on power failure
- [ ] Add UPS notification to alert on power failure

## Infrastructure (atlas)

- [ ] Configure atlas as general purpose server (Docker, services, etc.)
- [ ] Secure atlas (firewall, fail2ban, etc.)
- [ ] Set up DNS/internal domain (Pi-hole, AdGuard, or CoreDNS)

## Talos/Kubernetes Cluster (managed via Flux)

- [ ] Install CNI (replace default Flannel with Cilium or Calico)
- [ ] Set up persistent storage (Rook/Ceph or Longhorn)
- [ ] Deploy ingress controller (Traefik or NGINX)
- [ ] Set up certificate management (cert-manager)
- [ ] Deploy monitoring stack (Prometheus + Grafana)
- [ ] Set up logging (Loki or EFK stack)
- [ ] Configure cluster backup strategy (etcd + Velero)
- [ ] Deploy a dashboard (Kuberneted Web UI)
- [ ] Enable scheduling on control planes  <!-- done but needs note -->
- [ ] Harden cluster security (network policies, RBAC, etc.)

## PXE/Network Boot

- [ ] Clean up PXE server configs (remove debug parameters)
- [ ] Automate Talos asset downloads (CI/CD or cron)
- [ ] Document PXE boot flow for future reinstall

## General

- [ ] Create network diagram
- [ ] Document disaster recovery procedures
