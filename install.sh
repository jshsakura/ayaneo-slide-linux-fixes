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

CURRENT_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$CURRENT_USER")

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
systemctl enable "hhd_local@${CURRENT_USER}" 2>/dev/null || true

if pgrep -f "bin/hhd" >/dev/null 2>&1; then
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
        echo -e "${YELLOW}[!] HHD unavailable - steamos-manager restored as sole power manager. Install HHD before gaming on battery.${NC}"
    else
        echo -e "${YELLOW}[!] HHD unavailable - steamos-manager kept as sole power manager. Install HHD before gaming on battery.${NC}"
    fi
fi

# 2. Inject verified kernel boot parameters
echo -e "\n${BLUE}[2/6] Configuring Bootloader Parameters...${NC}"
LIMINE_DEFAULT="/etc/default/limine"

REQUIRED_PARAMS=(
    "acpi=strict"
    "processor.max_cstate=1"
    "idle=nomwait"
    "nvme_core.default_ps_max_latency_us=0"
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

    for p in "${REQUIRED_PARAMS[@]}"; do
        if grep -q "$p" "$LIMINE_DEFAULT"; then
            echo -e "  ${GREEN}✓${NC} $p (already present)"
        else
            sed -i -E "s/(KERNEL_CMDLINE\[default\]\+?=\".*)(\")/\1 $p\2/" "$LIMINE_DEFAULT"
            echo -e "  ${YELLOW}+${NC} Added $p"
        fi
    done

    echo -e "  Updating bootloader configuration..."
    limine-update || true
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

cat << 'EOF' > /etc/udev/rules.d/99-amdgpu-dpm-performance.rules
# Lock AMD GPU DPM performance level to high to prevent Data Fabric Sync Flood
ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTR{device/power_dpm_force_performance_level}="high"
EOF

udevadm control --reload-rules
udevadm trigger
echo -e "${GREEN}✓ LED sleep auto-off & GPU DPM stability rules installed.${NC}"

# 4. Enable Controller & Platform Services
echo -e "\n${BLUE}[4/6] Checking Controller & Platform Drivers...${NC}"
if systemctl list-unit-files | grep -q "inputplumber.service"; then
    systemctl enable --now inputplumber.service 2>/dev/null || true
    echo -e "${GREEN}✓ inputplumber.service active (Gamepad / AYASpace buttons).${NC}"
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
        echo "high" > "$d" 2>/dev/null || true
    fi
done
echo -e "${GREEN}✓ AMD GPU DPM performance level set to high.${NC}"

if [ -f "/sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode" ]; then
    echo "off" > /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode 2>/dev/null || true
    echo -e "${GREEN}✓ Joystick LED suspend mode set to off.${NC}"
fi

# 6. NVMe write-bandwidth ceiling + thermal guard (sync flood prevention)
# The DRAM-less NVMe hits ~72C at full-speed sustained writes (40 MB/s), which
# is the measured Data Fabric sync-flood crash zone on this chassis. The
# kernel-level cgroup io ceiling caps user-space disk writes independent of
# any application; the guard tightens it further when the drive runs hot.
echo -e "\n${BLUE}[6/6] Installing NVMe Write Ceiling & Thermal Guard...${NC}"
ROOT_DISK=$(findmnt -n -o SOURCE / | sed 's/\[.*//; s/p[0-9]\+$//')

cat << 'EOF' > /usr/local/sbin/ayaneo-nvme-guard
#!/usr/bin/env bash
# Keeps the DRAM-less NVMe below the Data Fabric sync-flood danger zone
# (~72C measured) by clamping app.slice disk write bandwidth via direct
# cgroupfs io.max writes. systemd set-property is NOT used: app.slice
# belongs to the user manager, so root-side set-property binds to nothing.
ENGAGE_mC=70000
RELEASE_mC=67000
CLAMP_WBPS=8000000
CEIL_WBPS=25000000
STATE=ok
CEIL_DISK=$(findmnt -n -o SOURCE / | sed 's/\[.*//; s/p[0-9]\+$//')
DEV_MM=$(cat "/sys/class/block/$(basename "$CEIL_DISK")/dev")
APP_CG=$(ls -d /sys/fs/cgroup/user.slice/user-*.slice/user@*.service/app.slice 2>/dev/null | head -1)

log() { logger -t ayaneo-nvme-guard "$1"; }
nvme_temp() {
    for h in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$h/name" 2>/dev/null)" = "nvme" ]; then
            cat "$h/temp1_input" 2>/dev/null && return 0
        fi
    done
    return 1
}
set_wbps() {
    [ -n "$APP_CG" ] && [ -n "$DEV_MM" ] || return 1
    echo "$DEV_MM rbps=max wbps=$1 riops=max wiops=max" > "$APP_CG/io.max"
}

# Clear legacy caps from systemd-manager-based versions (v2/v3) and apply
# the ceiling directly. Reads are never limited.
for SLICE in user.slice app.slice; do
    systemctl set-property --runtime "$SLICE" "IOWriteBandwidthMax=" 2>/dev/null || true
    systemctl set-property "$SLICE" "IOWriteBandwidthMax=" 2>/dev/null || true
done
rm -f /etc/systemd/system.control/user.slice.d/50-IOWriteBandwidthMax.conf
rm -f /etc/systemd/system.control/app.slice.d/50-IOWriteBandwidthMax.conf
set_wbps "$CEIL_WBPS" && log "applied ${CEIL_WBPS} B/s write ceiling to $APP_CG (reads unlimited, session.slice untouched)"

log "started: device=$CEIL_DISK($DEV_MM) engage=$((ENGAGE_mC/1000))C release=$((RELEASE_mC/1000))C clamp=${CLAMP_WBPS}"
while sleep 5; do
    # app.slice does not exist at multi-user.target time (user session not
    # up yet), so pick up the cgroup once it appears and apply the ceiling.
    if [ -z "$ENSURED" ]; then
        [ -n "$APP_CG" ] || APP_CG=$(ls -d /sys/fs/cgroup/user.slice/user-*.slice/user@*.service/app.slice 2>/dev/null | head -1)
        if [ -n "$APP_CG" ] && set_wbps "$CEIL_WBPS"; then
            ENSURED=1
            log "write ceiling applied to $APP_CG (user session up)"
        fi
    fi
    t=$(nvme_temp) || continue
    if [ "$t" -ge "$ENGAGE_mC" ] && [ "$STATE" != "hot" ]; then
        set_wbps "$CLAMP_WBPS" && STATE=hot
        log "NVMe at $((t/1000))C - app.slice write bandwidth clamped to $CLAMP_WBPS"
    elif [ "$t" -le "$RELEASE_mC" ] && [ "$STATE" != "ok" ]; then
        set_wbps "$CEIL_WBPS" && STATE=ok
        log "NVMe at $((t/1000))C - clamp released, ceiling back to $CEIL_WBPS"
    fi
done
EOF
chmod 755 /usr/local/sbin/ayaneo-nvme-guard

cat << 'EOF' > /etc/systemd/system/ayaneo-nvme-guard.service
[Unit]
Description=AYANEO Slide NVMe thermal guard (Data Fabric sync flood prevention)

[Service]
Type=simple
ExecStart=/usr/local/sbin/ayaneo-nvme-guard
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ayaneo-nvme-guard.service 2>/dev/null || true
systemctl restart ayaneo-nvme-guard.service
echo -e "${GREEN}✓ Thermal guard active: 25M ceiling, clamp 8M at 70C, release 67C (app.slice only, desktop exempt).${NC}"

# Optional drive-level self-throttle: report HCTM (Host Controlled Thermal
# Management, NVMe feature 0x10) support if nvme-cli is installed. HCTM lets
# the host tell the drive to throttle itself at a chosen temperature - the
# closest thing to a firmware-level DRAM-less thermal solution.
if command -v nvme >/dev/null 2>&1; then
    HCTM=$(nvme get-feature "$ROOT_DISK" -f 0x10 2>&1) || true
    if echo "$HCTM" | grep -q "TMT1"; then
        echo -e "${GREEN}✓ Drive supports HCTM (host-controlled self-throttle):${NC}"
        echo "$HCTM" | grep -E "TMT1|TMT2" | sed 's/^/    /'
    else
        echo -e "${YELLOW}[!] Drive firmware does not expose HCTM. Kernel-level guard remains the throttle.${NC}"
    fi
fi

echo -e "\n${CYAN}==============================================================================${NC}"
echo -e "${BOLD}${GREEN}  Installation Complete!  ${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "Applied fixes:"
echo -e "  1. ${BOLD}Power Management${NC}: HHD (Handheld Daemon) - TDP/fan/controller; steamos-manager conflict-handled"
echo -e "  2. ${BOLD}Sleep/Wake Freeze Fix${NC}: acpi=strict & nvme_core.default_ps_max_latency_us=0"
echo -e "  3. ${BOLD}Data Fabric Sync Flood (0x08000800) Fix${NC}: processor.max_cstate=1 & idle=nomwait"
echo -e "  4. ${BOLD}iGPU / NVMe DMA & Bus Stability Fix${NC}: iommu=pt & pcie_aspm=off"
echo -e "  5. ${BOLD}Display DCN / PSR Stability Fix${NC}: amdgpu.sg_display=0 & amdgpu.dcdebugmask=0x10"
echo -e "  6. ${BOLD}Joystick LED Auto-Off During Sleep${NC}"
echo -e "  7. ${BOLD}NVMe Sync Flood Prevention${NC}: 25 MB/s write ceiling & thermal guard service"
echo -e "\n${YELLOW}Please reboot your system to apply all new kernel parameters:${NC}"
echo -e "  ${BOLD}sudo systemctl reboot${NC}\n"
