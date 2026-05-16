#!/usr/bin/env bash
# Install and start Tailscale on atlas.
# Run via `make tailscale-atlas` from the repo root.
set -euo pipefail

# 1. Add Tailscale's official apt repo (idempotent)
if ! command -v tailscale >/dev/null 2>&1; then
  echo "==> Installing Tailscale..."
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
    | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
    | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq tailscale
else
  echo "==> Tailscale already installed: $(tailscale version | head -1)"
fi

# 2. Enable IPv4/IPv6 forwarding (required for exit node + subnet routing).
#    Persisted via /etc/sysctl.d so it survives reboots.
echo "==> Enabling IP forwarding for exit node..."
sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf >/dev/null

# 3. Enable and start the daemon
sudo systemctl enable --now tailscaled

# 4. Bring up the tailnet interface if not already authenticated.
#    Prints a one-time login URL you can open on any device.
if sudo tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
  echo "==> Tailscale is already up; reconfiguring flags..."
  sudo tailscale set \
    --advertise-exit-node \
    --ssh
  sudo tailscale status
else
  echo "==> Running 'tailscale up' (open the URL it prints in any browser)..."
  sudo tailscale up \
    --hostname=atlas \
    --ssh \
    --advertise-exit-node \
    --accept-dns=false
fi

echo "==> Done. Tailscale IP: $(tailscale ip -4 || true)"
