# Homelab

Infrastructure as code for a Proxmox home server.

## Hardware

- **Machine:** ASUS GL552JX laptop (2015)
- **CPU:** Intel i5-4200H (2C/4T, Haswell, 37W TDP)
- **RAM:** 16 GB DDR3L
- **Storage:** 256 GB M.2 SATA SSD (Proxmox + VMs) + 1 TB HDD (media)
- **GPU:** Intel HD 4600 (iGPU) + GTX 950M (dGPU, disabled via vfio-pci for power saving)
- **OS:** Proxmox VE 9.2.4 (Debian 13 Trixie)

## Network

| Host | IP | Purpose |
|------|----|---------|
| gl552jx (Proxmox host) | 192.168.1.252 | Hypervisor, Web UI :8006 |
| dns (LXC) | 192.168.1.10 | AdGuard Home — DNS filtering + ad blocking |
| monitor (LXC) | 192.168.1.12 | Gatus — uptime monitoring (:8080) |
| tailscale (LXC) | DHCP | Tailscale subnet router (192.168.1.0/24) |
| docker-host (VM) | DHCP | Debian 13 — Docker + Caddy + services |

- **Gateway:** 192.168.1.1 (VNPT iGate GW020-H)
- **Domain:** home.arpa
- **DNS:** All devices use AdGuard Home at 192.168.1.10

## Services

### Infrastructure (activated)
- **AdGuard Home** — Network-wide DNS ad blocking, DNS rewrites for `*.home.arpa`
- **Gatus** — Uptime monitoring with web dashboard
- **Tailscale** — VPN mesh + subnet router for remote access

### Docker services (planned)
- **Caddy** — Reverse proxy (HTTPS, `*.home.local`)
- **Beszel** — Resource monitoring (historical CPU/RAM/disk)
- **Vaultwarden** — Password manager
- **Jellyfin** — Media streaming (direct-play only)
- **Immich** — Photo management (ML disabled)
- **Paperless-ngx** — Document management (OCR scheduled)
- **SearXNG** — Private search engine
- **qBittorrent + Gluetun** — Media acquisition via VPN

## Quick Start

1. **Install Proxmox VE 9.x** on the laptop
2. **Run post-install config:** `bash proxmox/post-install.sh`
   - Disables lid-close suspend, screen blanking
   - Sets CPU governor to schedutil
   - Configures TLP + thermald for power/thermal management
   - Binds dGPU to vfio-pci for deep sleep
3. **Create LXCs:** `bash proxmox/lxc-create.sh`
   - AdGuard: 256 MB RAM, 2 GB disk
   - Gatus: 128 MB RAM, 2 GB disk
   - Tailscale: 128 MB RAM, 2 GB disk, nesting enabled
4. **Configure AdGuard** via web UI at `http://192.168.1.10:3000`
   - Reference blocklists and upstream DNS in `lxc/adguard/AdGuardHome.yaml`
5. **Configure Gatus** — config at `lxc/gatus/config.yaml`
   - Dashboard at `http://192.168.1.12:8080`
6. **Create Docker VM** and deploy services (see `vm/docker/`)

## Directory Structure

```
homelab/
├── README.md
├── .gitignore
├── proxmox/           # Host-level configs
│   ├── post-install.sh
│   └── lxc-create.sh
├── lxc/               # LXC service configs
│   ├── adguard/
│   │   └── AdGuardHome.yaml
│   ├── gatus/
│   │   └── config.yaml
│   └── tailscale/
│       └── setup.sh
├── vm/                # VM services (Docker Compose)
│   └── docker/
│       ├── caddy/
│       │   └── Caddyfile
│       ├── vaultwarden/
│       └── ...
├── scripts/           # Operational utilities
└── docs/              # Architecture decisions
    └── decisions.md
```

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Reverse proxy | Caddy (not NPM) | Lighter, auto-HTTPS, single binary |
| CPU governor | schedutil (GRUB kernel param) | Community preference, persists at boot |
| dGPU | vfio-pci bind (D3cold) | Deeper power saving than blacklist alone |
| Monitoring | Gatus (uptime) + Beszel (resources) | Lighter than Prometheus/Grafana |
| Docker install | docker-ce (official repo) | Not Debian's docker.io package |
| LXC swap | 0 | Community consensus — predictable RAM usage |
| LXC OS | Debian 13 | Matches Proxmox host base OS |
| DNS blocklists | ABPVN + hostsVN + HaGeZi Pro++ | Vietnamese + international coverage |

## References

- [Proxmox Helper Scripts](https://community-scripts.org/) — Community-maintained LXC/VM templates
- [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) — Network-wide ad blocking
- [Gatus](https://github.com/TwiN/gatus) — Developer-oriented health dashboard
- [Tailscale](https://tailscale.com/kb/1019/subnets) — Subnet router documentation
- [HaGeZi DNS Blocklists](https://github.com/hagezi/dns-blocklists) — Curated blocklists
