# Homelab Session Journal

**Date:** May 8, 2026
**Goal:** Set up homelab with 4 mini PCs — atlas (general server) + 3 Talos Kubernetes nodes

---

## Hardware

- **atlas** — HP EliteDesk 800 G2 DM 65W, 238GB SSD, Ubuntu 24.04 LTS
- **nova** — HP EliteDesk 800 G2 mini, Core i5-6500, 16GB RAM, 1TB NVMe
- **orbit** — HP EliteDesk 800 G2 mini, Core i5-6500, 16GB RAM, 1TB NVMe
- **comet** — HP EliteDesk 800 G2 mini, Core i5-6500, 16GB RAM, 1TB NVMe
- **UPS** — CyberPower CP1500PFCRM2U (1500VA/1000W)

---

## PXE Boot Server (atlas)

### Services

| Service | Role | Port |
|---------|------|------|
| dnsmasq | DHCP proxy (coexists with eero router) + TFTP | UDP 4011 (PXE), 69 (TFTP) |
| nginx | HTTP server for Talos boot assets | TCP 80 |

### dnsmasq Config (`pxe/configs/dnsmasq.conf`)

- DHCP proxy mode on subnet `192.168.1.0/24` — no IP leasing, just PXE options
- TFTP root at `/srv/tftp`
- Boot file: `ipxe.efi` (custom-built) for both UEFI (arch 7) and BIOS (arch 0)
- TFTP server IP: `192.168.1.229`

### nginx Config (`pxe/configs/nginx-pxe.conf`)

- Serves Talos kernel + initramfs from `/srv/http/talos/`
- Serves iPXE boot script from `/srv/http/pxe/`
- Config endpoint at `/config/` for future use

### Network Boot Flow

```
Mini PC PXE boot
  → DHCP from eero (port 67, gets IP)
  → PXE proxy from dnsmasq (port 4011, gets boot file info)
  → TFTP from atlas (downloads ipxe.efi, ~1.2MB)
  → Custom ipxe.efi runs embedded script:
      → DHCP (gets IP from eero)
      → HTTP GET /talos/v1.13.0/vmlinuz (20MB)
      → HTTP GET /talos/v1.13.0/initramfs.xz (82MB)
      → Boots Talos kernel with talos.platform=metal
  → Talos starts in maintenance mode (no config)
```

### Key Challenges Overcome

1. **HP EliteDesk 800 G2 BIOS PXE settings:**
   - Disable Secure Boot
   - Enable Network (PXE) Boot under Boot Options
   - Set Option ROM Launch Policy to All UEFI
   - Embedded LAN Controller must be Enabled
   - Press F9 for one-time boot menu, F10 for permanent

2. **DHCP proxy on eero network:**
   - dnsmasq in proxy mode on port 4011 (no conflict with eero on port 67)
   - Initial PXE clients detected by vendor class `PXEClient:Arch:00007:UNDI:003016`
   - Already-running iPXE detected by user class `iPXE` (option 77)

3. **iPXE chainloading loop:**
   - Stock Ubuntu `ipxe.efi` (Jan 2022) has EFI LoadFile2 bugs
   - Built custom `ipxe.efi` from latest iPXE source with embedded boot script
   - Embedded script eliminates need for iPXE to re-fetch config

4. **Initramfs not passed to kernel (VFS panic):**
   - Fixed by building fresh iPXE from source (latest Fixes for EFI LoadFile2 protocol)
   - Recompressed initramfs from Zstd to gzip (diagnostic step, not root cause)
   - Fresh build fixed it

5. **COMET BIOS settings not saving:**
   - Dead/stuck CMOS battery (two new CR2032s didn't help — likely stuck reset jumper)
   - Workaround: used one-time F9 boot menu
   - Old Ubuntu on sda was booting before Talos on nvme0n1
   - Fixed by wiping sda's boot sector with dd

### Provisioning Commands

```bash
# Full setup from scratch
make setup

# Or step by step:
make download-talos              # Download Talos v1.13.0 assets
make provision-pxe               # Install dnsmasq, nginx, ipxe on atlas
make deploy-pxe-cfg              # Copy configs to atlas
make upload-talos                # Upload Talos assets
# Then restart services on atlas
```

---

## Talos Kubernetes Cluster

### Node Details

| Node | Hostname | IP | Role | Disk |
|------|----------|-----|------|------|
| nova | nova | 192.168.1.234 | control-plane | /dev/nvme0n1 |
| orbit | orbit | 192.168.1.236 | control-plane | /dev/nvme0n1 |
| comet | comet | 192.168.1.239 | control-plane | /dev/nvme0n1 |

**Cluster Endpoint:** https://192.168.1.240:6443 (VIP, Layer 2)
**Kubernetes:** v1.36.0
**Talos:** v1.13.0

### Bootstrap Process

```bash
# Generate config with VIP
talosctl gen config homelab https://192.168.1.240:6443

# Apply to first node and bootstrap
talosctl apply-config --insecure --nodes 192.168.1.232 \
  --file controlplane.yaml --config-patch @patches/nova-patch.yaml
talosctl bootstrap --nodes 192.168.1.232

# Apply to remaining nodes
talosctl apply-config --insecure --nodes 192.168.1.226 --file orbit.yaml
talosctl apply-config --insecure --nodes 192.168.1.238 --file comet.yaml

# Enable scheduling on control planes
talosctl patch machineconfig -p '{"cluster":{"allowSchedulingOnControlPlanes":true}}'
```

### Key Config Values

**Hostname config:** Separate `HostnameConfig` document (not inline in machine config)
**Install disk:** `/dev/nvme0n1`
**VIP:** Layer 2 Virtual IP on interface `eno1` at `192.168.1.240`
**CNI:** Disabled Flannel (`cluster.network.cni.name: "none"`)

---

## Cilium CNI

**Version:** 1.19.3
**Mode:** With kube-proxy (`kubeProxyReplacement: false`)

### Helm Install Values

```yaml
ipam:
  mode: kubernetes
kubeProxyReplacement: false
securityContext:
  capabilities:
    ciliumAgent:
      - CHOWN, KILL, NET_ADMIN, NET_RAW, IPC_LOCK
      - SYS_ADMIN, SYS_RESOURCE, DAC_OVERRIDE
      - FOWNER, SETGID, SETUID
    cleanCiliumState:
      - NET_ADMIN, SYS_ADMIN, SYS_RESOURCE
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup
k8sServiceHost: 192.168.1.240
k8sServicePort: 6443
```

### Issues Resolved

1. **PodSecurity violation:** Talos enforces `baseline` by default, `kube-system` is exempt
2. **Capabilities not permitted:** Need explicit `securityContext.capabilities` (not just `privileged=true`)
3. **hostProc path:** Talos mounts `/proc` at `/hostproc` in containers
4. **Sysctl management disabled:** `sysctlOpts.enabled=false` due to Talos read-only `/proc/sys`
5. **Cilium_host veth creation:** Fixed by setting correct capabilities per Talos docs

---

## Flux v2 (GitOps)

**Repository:** github.com/zjpiazza/homelab
**Branch:** main
**Path:** clusters/homelab/flux-system/

### Bootstrap

```bash
flux bootstrap github \
  --owner=zjpiazza \
  --repository=homelab \
  --branch=main \
  --path=clusters/homelab \
  --personal
```

### Repository Structure

```
clusters/homelab/
└── flux-system/
    ├── gotk-components.yaml     # Flux core controllers
    ├── gotk-sync.yaml           # Sync Kustomization
    ├── kustomization.yaml       # Kustomize config
    ├── cilium-helm-repository.yaml  # Cilium Helm source
    └── cilium-helm-release.yaml     # Cilium install config (suspended)
```

**Note:** Cilium is currently installed via direct Helm (not Flux). The HelmRelease in the repo is suspended pending migration.

---

## UPS Monitoring (NUT)

**Detected:** CyberPower CP1500PFCRM2U on USB (vendor 0764, product 0601)
**Driver:** usbhid-ups
**Status:** OL CHRG (Online + Charging), 53% battery, 85 min runtime, 5% load

### Config Files

- `/etc/nut/nut.conf` — `MODE=netserver`
- `/etc/nut/ups.conf` — `[cyberpower]` section with driver, vendor/product IDs
- `/etc/nut/upsd.conf` — Listens on localhost + 192.168.1.229:3493
- `/etc/nut/upsd.users` — admin + monitor users
- `/etc/nut/upsmon.conf` — Primary monitoring, shutdown on low battery
- `/etc/udev/rules.d/99-nut-ups.rules` — USB permission for nut user

### Services

- `nut-driver@cyberpower.service` — USB driver
- `nut-server.service` — NUT daemon
- `nut-monitor.service` — Monitoring

---

## Project Structure

```
homelab/
├── Makefile              # Provisioning automation
├── backlog.md            # Task tracking
├── journal.md            # This file
├── .gitignore
├── pxe/
│   ├── configs/          # dnsmasq, nginx, boot.ipxe, grub.cfg
│   └── assets/           # Cached Talos vmlinuz + initramfs
├── talos/
│   ├── cluster/          # Generated configs, talosconfig, kubeconfig
│   └── patches/          # Node-specific config patches
└── clusters/
    └── homelab/
        └── flux-system/  # Flux GitOps manifests
```

**GitHub:** github.com/zjpiazza/homelab
