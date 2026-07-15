# Homelab

Infrastructure as code for a Proxmox VE 9.x home server on an ASUS GL552JX laptop.

## Hardware

- **Machine:** ASUS GL552JX laptop (2015)
- **CPU:** Intel i5-4200H (2C/4T, Haswell, 37W TDP)
- **RAM:** 16 GB DDR3L
- **Storage:** 256 GB M.2 SATA SSD (Proxmox + VMs) + 1 TB HDD (media)
- **GPU:** Intel HD 4600 (iGPU) + GTX 950M (dGPU, disabled via vfio-pci for power saving)
- **OS:** Proxmox VE 9.2.4 (Debian 13 Trixie)

## Network

| Host | IP (LAN) | IP (svcnet) | Purpose |
|------|----------|-------------|---------|
| gl552jx (Proxmox host) | 192.168.1.252 | 10.0.0.1 (gateway) | Hypervisor, Web UI :8006 |
| dns (LXC 101) | 192.168.1.10 | 10.0.0.10 | AdGuard Home — DNS filtering + ad blocking |
| monitor (LXC 102) | — | DHCP (10.0.0.101) | Gatus — uptime monitoring |
| caddy (LXC 103) | 192.168.1.254 | DHCP (10.0.0.102) | Reverse proxy — HTTP :80 + HTTPS :443 (internal cert) |
| tailscale (LXC 104) | — | DHCP (10.0.0.103) | Tailscale subnet router |
| docker-host (VM 100) | — | DHCP | Debian 13 — Docker services (planned) |

- **Gateway:** 192.168.1.1 (VNPT iGate GW020-H)
- **SDN svcnet:** 10.0.0.0/24, SNAT, gateway 10.0.0.1, DHCP pool 10.0.0.100-200
- **Domain:** `.home` (not `.home.arpa` — Android Tailscale DNS bug)
- **DNS:** All devices use AdGuard Home at 192.168.1.10
- **Tailscale IP:** `100.67.156.34` (stable — persists across reboots)

## DNS Architecture

```
Remote Client (Tailscale) → split DNS "home" → 192.168.1.10 (AdGuard) → LAN services
LAN Client               → router DHCP DNS → 192.168.1.10 (AdGuard) → LAN services
```

**AdGuard DNS rewrites:** `adguard.home → 192.168.1.10`, `proxmox.home → 192.168.1.252`, `*.home → 192.168.1.254`

**Caddy routes:**
- `http://gatus.home/` and `http://192.168.1.254/` → Gatus dashboard
- `http://adguard.home/` → AdGuard web UI
- `http://proxmox.home/` → Proxmox web UI
- `https://192.168.1.254/` → Gatus dashboard (TLS internal cert, for Android Chrome)

**Tailscale subnet router** (LXC 104, `100.67.156.34`) advertises: `10.0.0.0/24`, `192.168.1.10/32`, `192.168.1.254/32`

## Services

| Service | Status | Access |
|---------|--------|--------|
| AdGuard Home | ✅ Running | `http://adguard.home/`, `http://192.168.1.10/` |
| Gatus | ✅ Running | `http://gatus.home/`, `http://192.168.1.254/` |
| Tailscale | ✅ Running | Subnet router, split DNS |
| Caddy | ✅ Running | Reverse proxy on 192.168.1.254 |
| Docker | ⏳ Planned | VM 100, docker-ce from official repo |

## Directory Structure

```
homelab/
├── README.md
├── proxmox/
│   ├── post-install.sh              # Host post-install (lid close, CPU gov, dGPU, etc.)
│   ├── lxc-create.sh                # Data-driven LXC installer
│   ├── lxc-services/                # Drop .conf files to add/remove LXC services
│   │   ├── lxc-shared.conf           # Shared defaults (template, storage, bridge)
│   │   ├── adguard.conf
│   │   ├── gatus.conf
│   │   ├── caddy.conf
│   │   └── tailscale.conf
│   ├── lxc-configs/                 # Current LXC network configs (live)
│   │   ├── dns.conf
│   │   ├── monitor.conf
│   │   ├── caddy.conf
│   │   └── tailscale.conf
│   └── sdn/                         # SDN configuration
│       ├── zones.cfg
│       ├── vnets.cfg
│       ├── subnets.cfg
│       └── ethers                    # DHCP MAC→IP mappings
├── lxc/                             # Running service configs
│   ├── adguard/
│   │   └── AdGuardHome.yaml          # DNS rewrites, blocklists, upstreams
│   ├── gatus/
│   │   └── config.yaml               # Uptime monitoring endpoints
│   ├── caddy/
│   │   └── Caddyfile                 # Reverse proxy configuration
│   └── tailscale/
│       └── routes.env               # Advertised routes + Tailscale IP
├── vm/
│   └── docker/                       # Docker services (planned)
├── scripts/
└── docs/
```

## Quick Start

1. Install Proxmox VE 9.x
2. Run `bash proxmox/post-install.sh`
3. Create SDN: apply `proxmox/sdn/` configs
4. Create LXCs: `bash proxmox/lxc-create.sh`
5. Install per-LXC service configs from `lxc/<service>/`
6. Configure Tailscale: `tailscale up --advertise-routes=...` (see `lxc/tailscale/routes.env`)
7. Set up Tailscale admin: split DNS `home → 192.168.1.10`, approve routes

## Adding a new service

1. Drop a `.conf` file in `proxmox/lxc-services/`
2. Add Caddy reverse proxy block in `lxc/caddy/Caddyfile`
3. Add DNS rewrite in `lxc/adguard/AdGuardHome.yaml` (if needed)
4. Re-run `proxmox/lxc-create.sh <service>`
5. Commit all configs

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Reverse proxy | Caddy (own LXC) | Lighter than NPM, survives Docker VM reboots |
| Domain TLD | `.home` | Avoids `.home.arpa` Android Tailscale bug |
| HTTPS on Caddy | `tls internal` + `auto_https disable_redirects` | Internal cert for HSTS compatibility, no redirects |
| SDN | Simple Zone + SNAT | VLAN-free isolated homelab subnet |
| SDN DHCP | dnsmasq with MAC→IP pre-reservations | Stable IPs without static config on each host |
| CPU governor | schedutil (GRUB kernel param) | Community preference |
| dGPU | vfio-pci bind (D3cold) | Deeper power saving than blacklist alone |
| LXC swap | 0 | Predictable RAM usage, community consensus |
| Stateful filtering | Off by default (v1.98.8+) | Not needed for DNAT or subnet router |
