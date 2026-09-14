#!/usr/bin/env bash
# ==============================================================================
# AYANEO Slide (and Antec Core HS) Linux / CachyOS Community Fixes
# ==============================================================================
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${BOLD}${GREEN}  AYANEO Slide / Antec Core HS - Linux Community Fixes Installer  ${NC}"
echo -e "${CYAN}==============================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run with root privileges.${NC}"
    echo -e "Please run: ${YELLOW}curl -sSL https://raw.githubusercontent.com/jshsakura/ayaneo-slide-linux-fixes/main/install.sh | sudo bash${NC}"
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
USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)

# 1. Disable unstable background services
echo -e "\n${BLUE}[1/6] Power Management (HHD) & Unstable Daemons...${NC}"
if systemctl is-enabled scx_loader 2>/dev/null | grep -q "enabled"; then
    systemctl disable --now scx_loader 2>/dev/null || true
    echo -e "${GREEN}✓ scx_loader disabled. Reverted to standard Linux EEVDF scheduler.${NC}"
else
    echo -e "${GREEN}✓ scx_loader is already disabled.${NC}"
fi

# HHD (Handheld Daemon) is the required power manager: fan curves, TDP limits,
# controller and gyro, with official AYANEO Slide support. Without TDP limits,
# heavy 3D transients one-shot the 46Wh BMS into hard power-offs. It conflicts
# with steamos-manager (both claim the same controls), so the policy is:
# HHD present -> mask steamos-manager (plain disable is bypassed by Steam's
# D-Bus activation); HHD absent -> keep steamos-manager as the only power
# management and warn, because removing it with no replacement caused the
# battery power-off deaths.
if ! pgrep -f "bin/hhd" >/dev/null 2>&1 && ! sudo -u "$CURRENT_USER" -- bash -lc 'command -v hhd' >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] HHD not found - installing Handheld Daemon (official Slide support)...${NC}"
    sudo -u "$CURRENT_USER" -- bash -c 'curl -L https://raw.githubusercontent.com/hhd-dev/hhd/master/install.sh | bash' || true
fi
systemctl enable --now "hhd_local@${CURRENT_USER}" 2>/dev/null || true
# The HHD overlay UI is a bundled binary that dlopens libfuse.so.2; CachyOS
# ships fuse3 only, and without fuse2 the overlay thread dies on every boot.
pacman -S --needed --noconfirm fuse2 2>/dev/null || true

if systemctl is-active --quiet "hhd_local@${CURRENT_USER}"; then
    if [ "$(readlink -f /etc/systemd/system/steamos-manager.service 2>/dev/null)" != "/dev/null" ]; then
        systemctl disable --now steamos-manager 2>/dev/null || true
        systemctl mask steamos-manager
        echo -e "${GREEN}✓ HHD active - steamos-manager masked (conflicts over TDP/fan controls).${NC}"
    else
        echo -e "${GREEN}✓ HHD active - steamos-manager already masked.${NC}"
    fi
else
    if [ "$(readlink -f /etc/systemd/system/steamos-manager.service 2>/dev/null)" = "/dev/null" ]; then
        systemctl unmask steamos-manager
    fi
    systemctl enable --now steamos-manager 2>/dev/null || true
    if systemctl is-active --quiet steamos-manager; then
        echo -e "${YELLOW}[!] HHD unavailable - steamos-manager active as sole power manager. Install HHD before gaming on battery.${NC}"
    else
        echo -e "${RED}[ERROR] Neither HHD nor steamos-manager is active; refusing to leave the system without a power manager.${NC}"
        exit 1
    fi
fi

# 2. Inject verified kernel boot parameters
echo -e "\n${BLUE}[2/6] Configuring Bootloader Parameters...${NC}"
LIMINE_DEFAULT="/etc/default/limine"

REQUIRED_PARAMS=(
    "acpi=strict"
    "processor.max_cstate=1"
    "idle=nomwait"
    # The old value 0 avoided suspend-resume failures by disabling all APST.
    # NM7A1 PS3 totals 15 ms and PS4 totals 53 ms, so this restores the 50 mW
    # PS3 state while preserving the original workaround's PS4 exclusion.
    "nvme_core.default_ps_max_latency_us=15000"
    "tsc=reliable"
    "amdgpu.sg_display=0"
    "amdgpu.dcdebugmask=0x10"
    "iommu=pt"
    "pcie_aspm=off"
)

if [ -f "$LIMINE_DEFAULT" ]; then
    # Backup limine default
    if [ ! -f "${LIMINE_DEFAULT}.orig" ]; then
        cp "$LIMINE_DEFAULT" "${LIMINE_DEFAULT}.orig"
        echo -e "  + Created backup: ${LIMINE_DEFAULT}.orig"
    fi

    # Clean up obsolete or invalid parameters
    sed -i -E "s/[[:space:]]*amdgpu\.gfxoff=0//g" "$LIMINE_DEFAULT"
    # max_host_mem_size_mb was removed upstream in Linux 6.9: kernels >= 6.9
    # silently ignore it while still allocating the HMB, so strip it to avoid
    # false confidence that HMB is disabled.
    sed -i -E "s/[[:space:]]*nvme_core\.max_host_mem_size_mb=0//g" "$LIMINE_DEFAULT"
    # Replace older releases that disabled APST entirely. Keeping both values
    # would make behavior depend on kernel command-line parsing order.
    sed -i -E "s/[[:space:]]*nvme_core\.default_ps_max_latency_us=[^[:space:]\"]+//g" "$LIMINE_DEFAULT"

    for p in "${REQUIRED_PARAMS[@]}"; do
        if grep -q "$p" "$LIMINE_DEFAULT"; then
            echo -e "  ${GREEN}✓${NC} $p (already present)"
        else
            sed -i -E "s/(KERNEL_CMDLINE\[default\]\+?=\".*)(\")/\1 $p\2/" "$LIMINE_DEFAULT"
            echo -e "  ${YELLOW}+${NC} Added $p"
        fi
    done

    echo -e "  Updating bootloader configuration..."
    limine-update
    echo -e "${GREEN}✓ Limine bootloader successfully updated.${NC}"
else
    echo -e "${YELLOW}[!] /etc/default/limine not found. If using GRUB or systemd-boot, add:${NC}"
    echo -e "    ${BOLD}${REQUIRED_PARAMS[*]}${NC}"
fi

# 3. Install udev rules (Self-contained heredocs so curl | sudo bash works anywhere)
echo -e "\n${BLUE}[3/6] Installing Udev Rules...${NC}"
# Do not install a touchscreen LIBINPUT_CALIBRATION_MATRIX rule: KWin (Plasma
# Wayland) already applies the panel's 90-degree output transform to touch
# coordinates, so an extra udev matrix double-rotates touches off-target.

cat << 'EOF' > /etc/udev/rules.d/99-ayaneo-slide-led-suspend.rules
# Turn off joystick RGB LEDs during sleep to save battery
ACTION=="add|change", KERNEL=="ayaneo:rgb:joystick_rings", SUBSYSTEM=="leds", ATTR{suspend_mode}="off"
EOF

# HHD owns the APU power budget and GPU frequency policy. A permanent "high"
# DPM lock bypasses that policy, raises idle heat, and increases load transients.
rm -f /etc/udev/rules.d/99-amdgpu-dpm-performance.rules

udevadm control --reload-rules
udevadm trigger
echo -e "${GREEN}✓ LED sleep auto-off installed; GPU DPM delegated to HHD.${NC}"

# 4. Controller & Platform Services
echo -e "\n${BLUE}[4/6] Checking Controller & Platform Drivers...${NC}"
# InputPlumber and HHD are both controller-emulation layers over the raw
# gamepad: with both active, InputPlumber hides the device and HHD's emulated
# controller fails with 'Device or resource busy' every 3s, killing the HHD
# overlay (its trigger rides on the emulated controller). HHD has official
# Slide support (gyro, back buttons, QAM), so it wins when present.
if systemctl is-active --quiet "hhd_local@${CURRENT_USER}"; then
    if [ "$(readlink -f /etc/systemd/system/inputplumber.service 2>/dev/null)" != "/dev/null" ]; then
        systemctl disable --now inputplumber 2>/dev/null || true
        systemctl mask inputplumber
        echo -e "${GREEN}✓ inputplumber masked (D-Bus re-activation would resurrect plain disable; HHD owns controller emulation).${NC}"
    else
        echo -e "${GREEN}✓ inputplumber already masked (HHD owns controller emulation).${NC}"
    fi
else
    if systemctl list-unit-files | grep -q "inputplumber.service"; then
        systemctl enable --now inputplumber.service 2>/dev/null || true
        echo -e "${YELLOW}[!] HHD unavailable - inputplumber kept on for controller emulation.${NC}"
    fi
fi

# 5. Apply runtime mitigations immediately
echo -e "\n${BLUE}[5/6] Applying Runtime Mitigations...${NC}"
for d in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do
    if [ -f "$d" ]; then
        echo 1 > "$d" 2>/dev/null || true
    fi
done

for d in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
    if [ -f "$d" ]; then
        echo "auto" > "$d" 2>/dev/null || true
    fi
done
echo -e "${GREEN}✓ AMD GPU DPM performance level set to auto (managed inside HHD's TDP limit).${NC}"

if [ -f "/sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode" ]; then
    echo "off" > /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode 2>/dev/null || true
    echo -e "${GREEN}✓ Joystick LED suspend mode set to off.${NC}"
fi

# 6. NVMe latency-bounded APST and legacy bandwidth-limit cleanup
# The OEM NM7A1 advertises PS3 at 50 mW with 5 ms entry + 10 ms exit latency,
# and PS4 at 2.5 mW with 8 ms entry + 45 ms exit latency. A 15000 us latency
# ceiling therefore permits PS3 while excluding PS4 on that drive. Other NVMe
# models select whichever state fits the same latency bound. This reduces idle
# load without throttling I/O and preserves PCIe ASPM=off for link stability.
echo -e "\n${BLUE}[6/6] Configuring NVMe Shallow Power Saving...${NC}"
ROOT_DISK=$(findmnt -n -o SOURCE / | sed 's/\[.*//; s/p[0-9]\+$//')

# Remove the write limiter installed by releases prior to shallow APST.
systemctl disable --now ayaneo-nvme-guard.service 2>/dev/null || true
rm -f /etc/systemd/system/ayaneo-nvme-guard.service /usr/local/sbin/ayaneo-nvme-guard
DEV_MM=$(cat "/sys/class/block/$(basename "$ROOT_DISK")/dev" 2>/dev/null || true)
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

# Apply the new latency tolerance immediately as well as on the next boot.
# The per-controller PM QoS write makes the NVMe driver rebuild its APST table.
echo 15000 > /sys/module/nvme_core/parameters/default_ps_max_latency_us
for QOS in /sys/class/nvme/nvme*/power/pm_qos_latency_tolerance_us; do
    [ -f "$QOS" ] && echo 15000 > "$QOS"
done
echo -e "${GREEN}✓ NVMe APST limited to 15000 us; legacy write limits removed.${NC}"

echo -e "\n${CYAN}==============================================================================${NC}"
echo -e "${BOLD}${GREEN}  Installation Complete!  ${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "Applied fixes:"
echo -e "  1. ${BOLD}Power Management${NC}: HHD (Handheld Daemon) - TDP/fan/controller; steamos-manager conflict-handled"
echo -e "  2. ${BOLD}Sleep/Wake Freeze Fix${NC}: acpi=strict & shallow-only NVMe APST (15000 us)"
echo -e "  3. ${BOLD}CPU Idle-State Stability${NC}: processor.max_cstate=1 & idle=nomwait"
echo -e "  4. ${BOLD}iGPU / PCIe Stability${NC}: iommu=pt & pcie_aspm=off"
echo -e "  5. ${BOLD}Display DCN / PSR Stability Fix${NC}: amdgpu.sg_display=0 & amdgpu.dcdebugmask=0x10"
echo -e "  6. ${BOLD}Joystick LED Auto-Off During Sleep${NC}"
echo -e "  7. ${BOLD}NVMe Controller Idle Load Fix${NC}: 15000 us APST ceiling, no I/O cap"
echo -e "\n${YELLOW}Please reboot your system to apply all new kernel parameters:${NC}"
echo -e "  ${BOLD}sudo systemctl reboot${NC}\n"
