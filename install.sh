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

# 1. Disable unstable BPF CPU schedulers
echo -e "\n${BLUE}[1/5] Disabling unstable BPF scheduler (scx_loader)...${NC}"
if systemctl is-enabled scx_loader 2>/dev/null | grep -q "enabled"; then
    systemctl disable --now scx_loader 2>/dev/null || true
    echo -e "${GREEN}✓ scx_loader disabled. Reverted to standard Linux EEVDF scheduler.${NC}"
else
    echo -e "${GREEN}✓ scx_loader is already disabled.${NC}"
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
    "amdgpu.gfxoff=0"
)

if [ -f "$LIMINE_DEFAULT" ]; then
    # Backup limine default
    if [ ! -f "${LIMINE_DEFAULT}.orig" ]; then
        cp "$LIMINE_DEFAULT" "${LIMINE_DEFAULT}.orig"
        echo -e "  + Created backup: ${LIMINE_DEFAULT}.orig"
    fi

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
cat << 'EOF' > /etc/udev/rules.d/99-ayaneo-slide-touchscreen.rules
# AYANEO Slide Goodix Capacitive TouchScreen Calibration for Landscape
ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="Goodix Capacitive TouchScreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
EOF

cat << 'EOF' > /etc/udev/rules.d/99-ayaneo-slide-led-suspend.rules
# Turn off joystick RGB LEDs during sleep to save battery
ACTION=="add|change", KERNEL=="ayaneo:rgb:joystick_rings", SUBSYSTEM=="leds", ATTR{suspend_mode}="off"
EOF

udevadm control --reload-rules
udevadm trigger
echo -e "${GREEN}✓ Touchscreen calibration rule installed (/etc/udev/rules.d/99-ayaneo-slide-touchscreen.rules).${NC}"
echo -e "${GREEN}✓ LED sleep auto-off rule installed (/etc/udev/rules.d/99-ayaneo-slide-led-suspend.rules).${NC}"

# 4. Enable Controller & Platform Services
echo -e "\n${BLUE}[4/5] Checking Controller & Platform Drivers...${NC}"
if systemctl list-unit-files | grep -q "inputplumber.service"; then
    systemctl enable --now inputplumber.service 2>/dev/null || true
    echo -e "${GREEN}✓ inputplumber.service active (Gamepad / AYASpace buttons).${NC}"
fi

# 5. Apply runtime mitigations immediately
echo -e "\n${BLUE}[5/5] Applying Runtime Mitigations...${NC}"
for d in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do
    if [ -f "$d" ]; then
        echo 1 > "$d" 2>/dev/null || true
    fi
done

if [ -f "/sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode" ]; then
    echo "off" > /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode 2>/dev/null || true
    echo -e "${GREEN}✓ Joystick LED suspend mode set to off.${NC}"
fi

echo -e "\n${CYAN}==============================================================================${NC}"
echo -e "${BOLD}${GREEN}  Installation Complete!  ${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "Applied fixes:"
echo -e "  1. ${BOLD}Sleep/Wake Freeze Fix${NC}: acpi=strict & nvme_core.default_ps_max_latency_us=0"
echo -e "  2. ${BOLD}Data Fabric Sync Flood (0x08000800) Fix${NC}: processor.max_cstate=1 & idle=nomwait"
echo -e "  3. ${BOLD}Touchscreen Landscape Calibration Matrix${NC}"
echo -e "  4. ${BOLD}Joystick LED Auto-Off During Sleep${NC}"
echo -e "\n${YELLOW}Please reboot your system to apply all new kernel parameters:${NC}"
echo -e "  ${BOLD}sudo systemctl reboot${NC}\n"
