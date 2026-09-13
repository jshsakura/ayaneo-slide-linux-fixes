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

# Remove udev rules
echo "Removing custom udev rules..."
rm -f /etc/udev/rules.d/99-ayaneo-slide-touchscreen.rules
rm -f /etc/udev/rules.d/99-ayaneo-slide-led-suspend.rules
udevadm control --reload-rules
echo "✓ Udev rules removed."

# Remove NVMe thermal guard and write ceiling
systemctl disable --now ayaneo-nvme-guard.service 2>/dev/null || true
rm -f /etc/systemd/system/ayaneo-nvme-guard.service
rm -f /usr/local/sbin/ayaneo-nvme-guard
DEV_MM=$(cat "/sys/class/block/$(basename "$(findmnt -n -o SOURCE / | sed 's/\[.*//; s/p[0-9]\+$//')")/dev" 2>/dev/null)
for CG in /sys/fs/cgroup/user.slice/user-*.slice/user@*.service/app.slice; do
    [ -n "$DEV_MM" ] && echo "$DEV_MM rbps=max wbps=max riops=max wiops=max" > "$CG/io.max" 2>/dev/null
done
for SLICE in app.slice user.slice; do
    systemctl set-property --runtime "$SLICE" "IOWriteBandwidthMax=" 2>/dev/null || true
    systemctl set-property "$SLICE" "IOWriteBandwidthMax=" 2>/dev/null || true
done
rm -f /etc/systemd/system.control/app.slice.d/50-IOWriteBandwidthMax.conf
rm -f /etc/systemd/system.control/user.slice.d/50-IOWriteBandwidthMax.conf
systemctl daemon-reload
echo "✓ NVMe thermal guard removed and write bandwidth limits cleared."

# Restore masked vendor service only when HHD is not providing power
# management; unmasking while HHD runs recreates the TDP/fan conflict.
if pgrep -f "bin/hhd" >/dev/null 2>&1; then
    echo "✓ HHD running - steamos-manager stays masked (conflict)."
elif [ "$(readlink -f /etc/systemd/system/steamos-manager.service 2>/dev/null)" = "/dev/null" ]; then
    systemctl unmask steamos-manager
    systemctl enable steamos-manager 2>/dev/null || true
    echo "✓ steamos-manager unmasked and re-enabled."
fi

# Restore bootloader if backup exists
if [ -f /etc/default/limine.orig ]; then
    echo "Restoring original Limine configuration..."
    cp -f /etc/default/limine.orig /etc/default/limine
    limine-update || true
    echo "✓ Original bootloader configuration restored."
fi

echo -e "${GREEN}✓ Rollback complete. Please reboot your system.${NC}"
