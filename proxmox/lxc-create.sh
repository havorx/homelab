#!/bin/bash
# Generic LXC installer — scans lxc-services/*.conf, creates selected LXCs
# Usage:
#   bash lxc-create.sh                    # Interactive menu (if TTY) or batch all
#   bash lxc-create.sh adguard gatus      # Install specific services
#   bash lxc-create.sh --list              # Show available services
set -e

CONF_DIR="$(dirname "$0")/lxc-services"
SHARED_CONF="$CONF_DIR/lxc-shared.conf"

[ -f "$SHARED_CONF" ] || { echo "ERROR: $SHARED_CONF not found"; exit 1; }
source "$SHARED_CONF"

# Discover available services (one per .conf file, excluding shared)
SERVICES=()
for conf in "$CONF_DIR"/*.conf; do
    [ -f "$conf" ] || continue
    name=$(basename "$conf" .conf)
    [ "$name" = "lxc-shared" ] && continue
    source "$conf"
    SERVICES+=("$name")
    NOTES["$name"]="${NOTE:-}"
    HOSTNAMES["$name"]="${HOSTNAME:-}"
    unset NOTE HOSTNAME
done

if [ ${#SERVICES[@]} -eq 0 ]; then
    echo "No .conf files found in $CONF_DIR"
    exit 1
fi

# --list mode
if [ "$1" = "--list" ]; then
    echo "Available services:"
    for s in "${SERVICES[@]}"; do
        echo "  $s — ${NOTES[$s]:-} (${HOSTNAMES[$s]:-})"
    done
    exit 0
fi

# Determine which services to install
SELECTED=()
if [ $# -gt 0 ]; then
    # CLI mode — install specified services
    for arg in "$@"; do
        if [[ " ${SERVICES[*]} " =~ " $arg " ]]; then
            SELECTED+=("$arg")
        else
            echo "Warning: unknown service '$arg', skipping"
        fi
    done
elif [ -t 0 ] && command -v whiptail &>/dev/null; then
    # TTY + whiptail available → interactive checklist
    MENU_ARGS=()
    for s in "${SERVICES[@]}"; do
        MENU_ARGS+=("$s" "${NOTES[$s]:-}" ON)
    done
    CHOICES=$(whiptail --title "LXC Installer" --checklist \
        "Select services to create:" 15 70 ${#SERVICES[@]} \
        "${MENU_ARGS[@]}" \
        3>&1 1>&2 2>&3) || exit 0
    for s in $CHOICES; do
        s="${s//\"/}"
        SELECTED+=("$s")
    done
else
    # No TTY and no args → batch install all
    SELECTED=("${SERVICES[@]}")
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "No services selected. Exiting."
    exit 0
fi

# Assign IDs sequentially
NEXTID=$(pvesh get /cluster/nextid 2>/dev/null || echo 100)
echo "=== Creating ${#SELECTED[@]} LXC(s) ==="
echo

for i in "${!SELECTED[@]}"; do
    svc="${SELECTED[$i]}"
    CONF="$CONF_DIR/$svc.conf"

    # Source service-specific config
    unset HOSTNAME MEMORY DISK NESTING KEYCTL STATIC_IP POST_CREATE NOTE
    source "$CONF"
    CT_ID=$((NEXTID + i))

    echo "--- $svc (ID: $CT_ID, ${MEMORY:-?} MB, ${DISK:-?} GB) ---"
    echo "  ${NOTE:-}"

    FEATURES=""
    [ "${NESTING:-0}" = "1" ] && FEATURES="nesting=1"
    [ "${KEYCTL:-0}" = "1" ] && FEATURES="${FEATURES}${FEATURES:+,}keyctl=1"

    FEAT_FLAG=""
    [ -n "$FEATURES" ] && FEAT_FLAG="--features $FEATURES"

    pct create "$CT_ID" "$TEMPLATE" \
        --hostname "${HOSTNAME:-$svc}" \
        --ssh-public-keys "$SSH_KEY" \
        --memory "${MEMORY:-512}" --swap "${SWAP:-0}" \
        --cores "${CORES:-1}" \
        --rootfs "${STORAGE:-local-lvm}:${DISK:-4}" \
        --net0 "name=eth0,bridge=${BRIDGE:-vmbr0},ip=dhcp,ip6=static" \
        --unprivileged "${UNPRIVILEGED:-1}" \
        --onboot "${ONBOOT:-1}" \
        --start 1 \
        ${FEAT_FLAG}

    # Set static IP if defined
    if [ -n "${STATIC_IP:-}" ]; then
        pct set "$CT_ID" --net0 "name=eth0,bridge=${BRIDGE:-vmbr0},ip=${STATIC_IP}/24,gw=192.168.1.1,ip6=static"
        echo "  Static IP: ${STATIC_IP}"
    fi

    # Run post-create commands (e.g., TUN device for Tailscale)
    if [ -n "${POST_CREATE:-}" ]; then
        eval "$POST_CREATE"
        echo "  Post-create config applied"
    fi

    echo "  Done."
    echo
done

echo "=== Finished ==="
pct list | grep -E "^${NEXTID}|$(echo "${SELECTED[*]}" | tr ' ' '|')"
echo
echo "IDs assigned:"
for i in "${!SELECTED[@]}"; do
    echo "  $((NEXTID + i)) = ${SELECTED[$i]} (${HOSTNAMES[${SELECTED[$i]}]:-})"
done
