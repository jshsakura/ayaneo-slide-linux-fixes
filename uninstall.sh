#!/usr/bin/env bash
# ==============================================================================
# AYANEO Slide Linux Fixes Rollback / Uninstaller
# ==============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}  AYANEO Slide Fixes - Rollback / Uninstall  ${NC}"
echo -e "${CYAN}====================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run with root privileges.${NC}"
    echo -e "Please run: sudo bash $0"
    exit 1
fi

if [ -n "${SUDO_USER:-}" ]; then
    CURRENT_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
    CURRENT_USER=$(id -nu "$PKEXEC_UID")
else
    CURRENT_USER=$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')
    CURRENT_USER="${CURRENT_USER:-$USER}"
fi
CURRENT_UID=$(id -u "$CURRENT_USER")
STATE_DIR=/var/lib/ayaneo-slide-linux-fixes
ADDED_PARAMS_FILE="$STATE_DIR/limine-added-params"
user_systemctl() {
    local runtime_dir="/run/user/${CURRENT_UID}"
    [ -S "${runtime_dir}/bus" ] || return 1
    sudo -u "$CURRENT_USER" -- env \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
        systemctl --user "$@"
}

if [ -f "$STATE_DIR/scx_loader.was_enabled" ]; then
    systemctl enable --now scx_loader.service 2>/dev/null || true
    rm -f "$STATE_DIR/scx_loader.was_enabled"
    echo "✓ scx_loader restored to its pre-install enabled state."
fi

# Remove udev rules
echo "Removing custom udev rules..."
rm -f /etc/udev/rules.d/99-ayaneo-slide-led-suspend.rules
udevadm control --reload-rules
echo "✓ Udev rules removed."

# Restore inputplumber as the controller layer when HHD is not running
if ! pgrep -f "bin/hhd" >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q "inputplumber.service"; then
    if [ "$(readlink -f /etc/systemd/system/inputplumber.service 2>/dev/null)" = "/dev/null" ]; then
        systemctl unmask inputplumber
    fi
    systemctl enable --now inputplumber.service 2>/dev/null || true
    echo "✓ inputplumber unmasked and re-enabled (HHD absent)."
fi

# Remove migration leftovers created by installer releases before shallow APST.
systemctl disable --now ayaneo-nvme-guard.service 2>/dev/null || true
rm -f /etc/systemd/system/ayaneo-nvme-guard.service
rm -f /usr/local/sbin/ayaneo-nvme-guard
DEV_MM=$(cat "/sys/class/block/$(basename "$(findmnt -n -o SOURCE / | sed 's/\[.*//; s/p[0-9]\+$//')")/dev" 2>/dev/null || true)
for CG in /sys/fs/cgroup/user.slice/user-*.slice/user@*.service/app.slice; do
    [ -d "$CG" ] || continue
    [ -n "$DEV_MM" ] && echo "$DEV_MM rbps=max wbps=max riops=max wiops=max" > "$CG/io.max" 2>/dev/null || true
done
for SLICE in app.slice user.slice; do
    systemctl set-property --runtime "$SLICE" "IOWriteBandwidthMax=" 2>/dev/null || true
    systemctl set-property "$SLICE" "IOWriteBandwidthMax=" 2>/dev/null || true
done
rm -f /etc/systemd/system.control/app.slice.d/50-IOWriteBandwidthMax.conf
rm -f /etc/systemd/system.control/user.slice.d/50-IOWriteBandwidthMax.conf
systemctl daemon-reload
echo "✓ Legacy NVMe limiter artifacts removed."

# Restore masked vendor service only when HHD is not providing power
# management; unmasking while HHD runs recreates the TDP/control conflict.
if pgrep -f "bin/hhd" >/dev/null 2>&1; then
    echo "✓ HHD running - system and user steamos-manager units stay masked."
else
    systemctl disable --now steamos-manager.service 2>/dev/null || true
    systemctl unmask steamos-manager.service 2>/dev/null || true
    user_systemctl unmask steamos-manager.service 2>/dev/null || true
    if user_systemctl enable --now steamos-manager.service 2>/dev/null && \
       user_systemctl is-active --quiet steamos-manager.service; then
        echo "✓ steamos-manager user unit restored."
    else
        systemctl enable --now steamos-manager.service 2>/dev/null || true
        if systemctl is-active --quiet steamos-manager.service; then
            echo "✓ steamos-manager system unit restored."
        else
            echo "[!] steamos-manager could not be restored; install a power manager before gaming."
        fi
    fi
fi

# Remove only parameters recorded as additions by this installer. Restoring an
# old .orig file wholesale can discard unrelated boot changes made afterward.
if [ -f /etc/default/limine ] && [ -s "$ADDED_PARAMS_FILE" ]; then
    echo "Removing installer-added Limine parameters..."
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        escaped=${p//./\\.}
        sed -i -E "s/(^|[[:space:]])${escaped}([[:space:]\"]|$)/\\1\\2/g" /etc/default/limine
    done < "$ADDED_PARAMS_FILE"
    rm -f "$ADDED_PARAMS_FILE"
    limine-update || true
    echo "✓ Installer-added Limine parameters removed; later boot changes preserved."
elif [ -f /etc/default/limine.orig ]; then
    echo "[!] Legacy .orig backup retained. It was not restored because doing so could overwrite later boot changes."
fi

echo -e "${GREEN}✓ Rollback complete. Please reboot your system.${NC}"
