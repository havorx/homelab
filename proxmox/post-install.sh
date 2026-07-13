#!/bin/bash
# Post-install configuration for Proxmox VE on laptop hardware
# Run once after Proxmox installation, before creating any VMs/LXCs
# Reboot required after execution for vfio-pci + GRUB changes
set -e

echo "=== Fix 1: Lid-close + sleep prevention ==="
sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sed -i 's/#HandleSuspendKey=suspend/HandleSuspendKey=ignore/' /etc/systemd/logind.conf
echo -e "AllowSuspend=no\nAllowHibernation=no" >> /etc/systemd/sleep.conf
systemctl restart systemd-logind

echo "=== Fix 2: Free repo + disable subscription nag ==="
rm -f /etc/apt/sources.list.d/pve-enterprise.sources
cat > /etc/apt/sources.list.d/pve-no-subscription.sources << 'REPO'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
REPO

# Remove subscription nag from web UI (desktop + mobile)
mkdir -p /usr/local/bin
cat > /usr/local/bin/pve-remove-nag.sh << 'SCRIPT'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi
MOBILE_TPL=/usr/share/pve-yew-mobile-gui/index.html.tpl
MARKER="<!-- MANAGED BLOCK FOR MOBILE NAG -->"
if [ -f "$MOBILE_TPL" ] && ! grep -q "$MARKER" "$MOBILE_TPL"; then
    printf "%s\n" "$MARKER" "<script>" \
      "  function removeSubscriptionElements() {" \
      "    const dialogs = document.querySelectorAll('dialog.pwt-outer-dialog');" \
      "    dialogs.forEach(dialog => { if ((dialog.textContent || '').toLowerCase().includes('subscription')) { dialog.remove(); } });" \
      "    const cards = document.querySelectorAll('.pwt-card.pwt-p-2');" \
      "    cards.forEach(card => { if (!card.querySelector('button') && (card.textContent||'').toLowerCase().includes('subscription')) { card.remove(); } });" \
      "  }" \
      "  new MutationObserver(removeSubscriptionElements).observe(document.body, {childList:true,subtree:true});" \
      "  removeSubscriptionElements(); setInterval(removeSubscriptionElements, 300);" \
      "</script>" >> "$MOBILE_TPL"
fi
apt --reinstall install proxmox-widget-toolkit -y > /dev/null 2>&1
SCRIPT
chmod 755 /usr/local/bin/pve-remove-nag.sh
/usr/local/bin/pve-remove-nag.sh
cat > /etc/apt/apt.conf.d/no-nag-script << 'NAG'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
NAG
chmod 644 /etc/apt/apt.conf.d/no-nag-script

echo "=== Fix 3: CPU governor (schedutil) + screen blanking ==="
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet consoleblank=300 cpufreq.default_governor=schedutil"/' /etc/default/grub
update-grub
echo schedutil | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null

echo "=== Fix 4: Thermal + battery management ==="
apt install -y tlp thermald lm-sensors
sed -i 's/^#START_CHARGE_THRESH_BAT0=.*/START_CHARGE_THRESH_BAT0=0  # dummy — ASUS only supports stop threshold/' /etc/tlp.conf
sed -i 's/^#STOP_CHARGE_THRESH_BAT0=.*/STOP_CHARGE_THRESH_BAT0=80/' /etc/tlp.conf
systemctl enable --now thermald tlp

echo "=== Fix 5: dGPU vfio-pci binding for D3cold deep sleep ==="
echo "options vfio-pci ids=10de:139a disable_vga=1" > /etc/modprobe.d/vfio.conf
cat > /etc/modprobe.d/blacklist-nvidia.conf << 'BLACKLIST'
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
BLACKLIST
echo -e "vfio\nvfio_iommu_type1\nvfio_pci" >> /etc/modules
update-initramfs -u -k all

echo "=== Fix 6: Update everything ==="
apt update && apt dist-upgrade -y

echo ""
echo "=== Done. Reboot for vfio-pci + GRUB + consoleblank to take effect. ==="
