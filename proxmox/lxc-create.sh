#!/bin/bash
# Create all LXC containers for the homelab
# Run on Proxmox host after post-install.sh
# Template must be pre-downloaded:
#   pveam download local debian-13-standard
set -e

TEMPLATE="local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
STORAGE="local-lvm"
BRIDGE="vmbr0"
SEARCHDOMAIN="home.arpa"
NAMESERVER="192.168.1.1"

echo "=== Creating AdGuard LXC ==="
pct create <adguard-id> $TEMPLATE \
  --hostname dns --password <password> \
  --ssh-public-keys /tmp/opencode.pub \
  --memory 256 --swap 0 --cores 1 \
  --rootfs $STORAGE:2 \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp,ip6=static \
  --unprivileged 1 --onboot 1 \
  --start 1

echo "=== Creating Gatus LXC ==="
pct create <gatus-id> $TEMPLATE \
  --hostname monitor --password <password> \
  --ssh-public-keys /tmp/opencode.pub \
  --memory 128 --swap 0 --cores 1 \
  --rootfs $STORAGE:2 \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp,ip6=static \
  --unprivileged 1 --onboot 1 \
  --start 1

echo "=== Creating Tailscale LXC ==="
pct create <tailscale-id> $TEMPLATE \
  --hostname tailscale --password <password> \
  --ssh-public-keys /tmp/opencode.pub \
  --memory 128 --swap 0 --cores 1 \
  --rootfs $STORAGE:2 \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp,ip6=static \
  --unprivileged 1 --onboot 1 \
  --features nesting=1,keyctl=1 \
  --start 1

# TUN device access for Tailscale
cat >> /etc/pve/lxc/<tailscale-id>.conf << 'EOF'
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF

echo "=== Done. LXC IDs shown by 'pct list' ==="
