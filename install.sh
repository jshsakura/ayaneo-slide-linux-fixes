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
echo -e "\n${BLUE}[1/5] Disabling unstable background daemons...${NC}"
if systemctl is-enabled scx_loader 2>/dev/null | grep -q "enabled"; then
    systemctl disable --now scx_loader 2>/dev/null || true
    echo -e "${GREEN}✓ scx_loader disabled. Reverted to standard Linux EEVDF scheduler.${NC}"
else
    echo -e "${GREEN}✓ scx_loader is already disabled.${NC}"
fi

# Mask instead of disable: Steam re-activates this unit through the
# com.steampowered.SteamOSManager1 D-Bus interface on every boot, which
# silently bypasses plain 'disable'. Only a mask blocks that path.
if [ "$(readlink -f /etc/systemd/system/steamos-manager.service 2>/dev/null)" = "/dev/null" ]; then
    echo -e "${GREEN}✓ steamos-manager is already masked.${NC}"
else
    systemctl disable --now steamos-manager 2>/dev/null || true
    systemctl mask steamos-manager
    echo -e "${GREEN}✓ steamos-manager masked (blocks Steam D-Bus re-activation; prevents invalid GPU clock DPM calls on 7840U).${NC}"
fi

# 2. Inject verified kernel boot parameters
echo -e "\n${BLUE}[2/5] Configuring Bootloader Parameters...${NC}"
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
echo -e "\n${BLUE}[3/5] Installing Udev Rules...${NC}"
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

# v3: cap app.slice only (Steam, browsers, user apps). Plasma/KWin/IME live in
# session.slice and stay uncapped, and reads are never limited (rbps=max).
# Migrate away the v2 user.slice cap that stalled the whole desktop.
systemctl set-property --runtime app.slice "IOWriteBandwidthMax=" 2>/dev/null || true
systemctl set-property user.slice "IOWriteBandwidthMax=" 2>/dev/null || true
rm -f /etc/systemd/system.control/user.slice.d/50-IOWriteBandwidthMax.conf

systemctl set-property app.slice "IOWriteBandwidthMax=$ROOT_DISK 25M"
echo -e "${GREEN}✓ Persistent app.slice write ceiling: 25 MB/s on $ROOT_DISK (Plasma/IME uncapped, reads unlimited).${NC}"

cat << 'EOF' > /usr/local/sbin/ayaneo-nvme-guard
#!/usr/bin/env bash
# Keeps the DRAM-less NVMe below the Data Fabric sync-flood danger zone
# (~72C measured) by dynamically clamping user.slice disk write bandwidth.
ENGAGE_mC=74000
RELEASE_mC=70000
CLAMP_RATE=8M
STATE=ok
CEIL_DEV=$(findmnt -n -o SOURCE / | sed 's/\[.*//; s/p[0-9]\+$//')

log() { logger -t ayaneo-nvme-guard "$1"; }
nvme_temp() {
    for h in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$h/name" 2>/dev/null)" = "nvme" ]; then
            cat "$h/temp1_input" 2>/dev/null && return 0
        fi
    done
    return 1
}

# Sync stale state: clear any runtime clamp a previous guard instance left
# behind when the drive is already below the engage threshold.
t0=$(nvme_temp) || t0=0
if [ "$t0" -lt "$ENGAGE_mC" ]; then
    systemctl set-property --runtime app.slice "IOWriteBandwidthMax=" 2>/dev/null || true
fi

log "started: device=$CEIL_DEV engage=$((ENGAGE_mC/1000))C release=$((RELEASE_mC/1000))C clamp=$CLAMP_RATE"
while sleep 5; do
    t=$(nvme_temp) || continue
    if [ "$t" -ge "$ENGAGE_mC" ] && [ "$STATE" != "hot" ]; then
        systemctl set-property --runtime app.slice "IOWriteBandwidthMax=$CEIL_DEV $CLAMP_RATE"
        STATE=hot
        log "NVMe at $((t/1000))C - write bandwidth clamped to $CLAMP_RATE"
    elif [ "$t" -le "$RELEASE_mC" ] && [ "$STATE" != "ok" ]; then
        systemctl set-property --runtime app.slice "IOWriteBandwidthMax="
        STATE=ok
        log "NVMe at $((t/1000))C - runtime clamp removed (persistent 25M ceiling remains)"
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
systemctl enable --now ayaneo-nvme-guard.service
echo -e "${GREEN}✓ Thermal guard active: clamp 8M at 74C, release at 70C - app.slice only (desktop stays responsive).${NC}"

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
echo -e "  1. ${BOLD}Sleep/Wake Freeze Fix${NC}: acpi=strict & nvme_core.default_ps_max_latency_us=0"
echo -e "  2. ${BOLD}Data Fabric Sync Flood (0x08000800) Fix${NC}: processor.max_cstate=1 & idle=nomwait"
echo -e "  3. ${BOLD}iGPU / NVMe DMA & Bus Stability Fix${NC}: iommu=pt & pcie_aspm=off"
echo -e "  4. ${BOLD}Display DCN / PSR Stability Fix${NC}: amdgpu.sg_display=0 & amdgpu.dcdebugmask=0x10"
echo -e "  5. ${BOLD}Joystick LED Auto-Off During Sleep${NC}"
echo -e "  6. ${BOLD}NVMe Sync Flood Prevention${NC}: 25 MB/s write ceiling & thermal guard service"
echo -e "\n${YELLOW}Please reboot your system to apply all new kernel parameters:${NC}"
echo -e "  ${BOLD}sudo systemctl reboot${NC}\n"
