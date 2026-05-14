ATLAS_IP ?= 192.168.1.229
TALOS_VERSION ?= v1.13.0
ARCH ?= amd64

.PHONY: all provision-pxe download-talos status tailscale-atlas

all: download-talos

# SSH helper
ssh-atlas = ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null d3adb0y@$(ATLAS_IP) sudo

# Download Talos boot assets to local cache
download-talos:
	@echo "==> Downloading Talos $(TALOS_VERSION) boot assets..."
	@mkdir -p pxe/assets
	@curl -sL -o pxe/assets/vmlinuz-$(ARCH) \
		"https://github.com/siderolabs/talos/releases/download/$(TALOS_VERSION)/vmlinuz-$(ARCH)"
	@curl -sL -o pxe/assets/initramfs-$(ARCH).xz \
		"https://github.com/siderolabs/talos/releases/download/$(TALOS_VERSION)/initramfs-$(ARCH).xz"
	@echo "==> Done. Assets cached in pxe/assets/"

# Deploy configurations to atlas and restart services
deploy-pxe-cfg:
	@echo "==> Deploying PXE configs to atlas..."
	@$(ssh-atlas) mkdir -p /srv/tftp /srv/tftp/pxe /srv/http/talos /srv/http/pxe
	@scp pxe/configs/dnsmasq.conf d3adb0y@$(ATLAS_IP):/tmp/dnsmasq.conf
	@$(ssh-atlas) cp /tmp/dnsmasq.conf /etc/dnsmasq.conf
	@scp pxe/configs/nginx-pxe.conf d3adb0y@$(ATLAS_IP):/tmp/nginx-pxe.conf
	@$(ssh-atlas) cp /tmp/nginx-pxe.conf /etc/nginx/sites-available/pxe
	@$(ssh-atlas) ln -sf /etc/nginx/sites-available/pxe /etc/nginx/sites-enabled/pxe
	@scp pxe/configs/boot.ipxe d3adb0y@$(ATLAS_IP):/srv/http/pxe/boot.ipxe
	@echo "==> Configs deployed."

# Upload Talos assets to atlas
upload-talos: download-talos
	@echo "==> Uploading Talos assets to atlas..."
	@$(ssh-atlas) mkdir -p /srv/http/talos/$(TALOS_VERSION)
	@scp pxe/assets/vmlinuz-$(ARCH) d3adb0y@$(ATLAS_IP):/srv/http/talos/$(TALOS_VERSION)/vmlinuz
	@scp pxe/assets/initramfs-$(ARCH).xz d3adb0y@$(ATLAS_IP):/srv/http/talos/$(TALOS_VERSION)/initramfs.xz
	@$(ssh-atlas) ln -sf /srv/http/talos/$(TALOS_VERSION) /srv/http/talos/current
	@echo "==> Assets uploaded."

# Set up atlas as a PXE server (full provisioning)
provision-pxe:
	@echo "==> Installing packages on atlas..."
	@$(ssh-atlas) apt-get update -qq
	@$(ssh-atlas) apt-get install -y -qq dnsmasq nginx ipxe
	@echo "==> Copying configs..."
	@$(ssh-atlas) cp /usr/lib/ipxe/ipxe.efi /srv/tftp/
	@$(ssh-atlas) cp /usr/lib/ipxe/undionly.kpxe /srv/tftp/
	@echo "==> Done. Run 'make deploy-pxe-cfg' then 'make upload-talos' to finish."
	@echo "    Then: $(ssh-atlas) systemctl restart dnsmasq nginx"

# Full setup: provision + config + assets + restart
setup: provision-pxe deploy-pxe-cfg upload-talos
	@echo "==> Restarting services..."
	@$(ssh-atlas) systemctl restart dnsmasq nginx
	@$(ssh-atlas) systemctl enable dnsmasq nginx
	@echo "==> PXE server setup complete on atlas."

# Check status of PXE services
status:
	@echo "--- dnsmasq ---"
	@$(ssh-atlas) systemctl status dnsmasq --no-pager 2>&1 | head -10
	@echo "--- nginx ---"
	@$(ssh-atlas) systemctl status nginx --no-pager 2>&1 | head -10
	@echo "--- TFTP files ---"
	@$(ssh-atlas) ls -la /srv/tftp/
	@echo "--- HTTP assets ---"
	@$(ssh-atlas) ls -la /srv/http/talos/current/

# Install and authenticate Tailscale on atlas.
# This is interactive: tailscale prints a login URL you open in any browser.
tailscale-atlas:
	@echo "==> Installing Tailscale on atlas ($(ATLAS_IP))..."
	@scp atlas/scripts/install-tailscale.sh d3adb0y@$(ATLAS_IP):/tmp/install-tailscale.sh
	@ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		d3adb0y@$(ATLAS_IP) 'bash /tmp/install-tailscale.sh'
