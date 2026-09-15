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
CURRENT_UID=$(id -u "$CURRENT_USER")
STATE_DIR=/var/lib/ayaneo-slide-linux-fixes
install -d -m 755 "$STATE_DIR"
ADDED_PARAMS_FILE="$STATE_DIR/limine-added-params"

# Control units owned by the logged-in user's systemd manager. SteamOS Manager
# ships both system and user units on CachyOS; masking only the system unit left
# the user unit D-Bus activatable and it retried five times on every login.
user_systemctl() {
    local runtime_dir="/run/user/${CURRENT_UID}"
    [ -S "${runtime_dir}/bus" ] || return 1
    sudo -u "$CURRENT_USER" -- env \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
        systemctl --user "$@"
}

# 1. Disable unstable background services
echo -e "\n${BLUE}[1/6] Power Management (HHD) & Unstable Daemons...${NC}"
if systemctl is-enabled scx_loader 2>/dev/null | grep -q "enabled"; then
    touch "$STATE_DIR/scx_loader.was_enabled"
    systemctl disable --now scx_loader 2>/dev/null || true
    echo -e "${GREEN}✓ scx_loader disabled. Reverted to standard Linux EEVDF scheduler.${NC}"
else
    echo -e "${GREEN}✓ scx_loader is already disabled.${NC}"
fi

# HHD (Handheld Daemon) is the required TDP/controller manager. The current
# Slide stack does not expose a PWM-controllable fan to HHD. The historical
# hard-power-off sessions happened without HHD managing the power budget. HHD
# conflicts with steamos-manager because both claim the same controls, so the
# policy is:
# HHD present -> mask steamos-manager (plain disable is bypassed by Steam's
# D-Bus activation); HHD absent -> keep steamos-manager as the only power
# management and warn, because removing it with no replacement caused the
# battery power-off deaths.
if ! pgrep -f "bin/hhd" >/dev/null 2>&1 && ! sudo -u "$CURRENT_USER" -- bash -lc 'command -v hhd' >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] HHD not found - installing Handheld Daemon (official Slide support)...${NC}"
    sudo -u "$CURRENT_USER" -- bash -c 'curl -L https://raw.githubusercontent.com/hhd-dev/hhd/master/install.sh | bash' || true
fi

# HHD searches ~/.local/bin before the system PATH. A stale local hhd-ui can
# therefore shadow a newer distribution package and leave the RC/QAM overlay
# dead after a gamescope-to-desktop transition. Prefer the packaged UI when it
# exists, while retaining HHD's normal discovery on installations without it.
HHD_UNIT="hhd_local@${CURRENT_USER}"
HHD_OVERLAY_DROPIN="/etc/systemd/system/hhd_local@.service.d/20-system-hhd-ui.conf"
HHD_WAS_ACTIVE=false
HHD_OVERLAY_CHANGED=false
systemctl is-active --quiet "$HHD_UNIT" && HHD_WAS_ACTIVE=true
if [ -x /usr/bin/hhd-ui ]; then
    if [ ! -f "$HHD_OVERLAY_DROPIN" ] || \
       [ "$(cat "$HHD_OVERLAY_DROPIN")" != $'[Service]\nEnvironment="HHD_OVERLAY=/usr/bin/hhd-ui"' ]; then
        install -d -m 755 "$(dirname "$HHD_OVERLAY_DROPIN")"
        cat << 'EOF' > "$HHD_OVERLAY_DROPIN"
[Service]
Environment="HHD_OVERLAY=/usr/bin/hhd-ui"
EOF
        HHD_OVERLAY_CHANGED=true
    fi
elif [ -f "$HHD_OVERLAY_DROPIN" ]; then
    rm -f "$HHD_OVERLAY_DROPIN"
    HHD_OVERLAY_CHANGED=true
fi
if $HHD_OVERLAY_CHANGED; then
    systemctl daemon-reload
fi
systemctl enable --now "$HHD_UNIT" 2>/dev/null || true
if $HHD_WAS_ACTIVE && $HHD_OVERLAY_CHANGED; then
    systemctl restart "$HHD_UNIT" 2>/dev/null || true
fi
if [ -x /usr/bin/hhd-ui ]; then
    echo -e "${GREEN}✓ HHD overlay pinned to the packaged /usr/bin/hhd-ui.${NC}"
fi
# The HHD overlay AppImage requires libfuse.so.2. Its daemon, controller and TDP
# paths remain independent if the optional overlay later exits with gamescope.
pacman -S --needed --noconfirm fuse2 2>/dev/null || true

if systemctl is-active --quiet "hhd_local@${CURRENT_USER}"; then
    systemctl disable --now steamos-manager.service 2>/dev/null || true
    systemctl mask --force steamos-manager.service 2>/dev/null || true
    user_systemctl disable --now steamos-manager.service 2>/dev/null || true
    user_systemctl mask --force steamos-manager.service 2>/dev/null || true
    user_systemctl reset-failed steamos-manager.service 2>/dev/null || true
    echo -e "${GREEN}✓ HHD active - system and user steamos-manager units masked.${NC}"

    # Preserve the user's selected sustained TDP, but remove the transient QAM
    # boost headroom used during the historical hard-power-off workload.
    HHDCTL="$USER_HOME/.local/share/hhd/venv/bin/hhdctl"
    if [ ! -x "$HHDCTL" ]; then
        HHDCTL=$(sudo -u "$CURRENT_USER" -- bash -lc 'command -v hhdctl' 2>/dev/null || true)
    fi
    if [ -x "$HHDCTL" ]; then
        for _ in {1..10}; do
            [ -S /run/hhd/api ] && break
            sleep 1
        done
        if [ -S /run/hhd/api ] && "$HHDCTL" set tdp.qam.boost=false >/dev/null 2>&1 && \
           [ "$("$HHDCTL" get tdp.qam.boost --values --sep='' 2>/dev/null)" = false ]; then
            echo -e "${GREEN}✓ HHD QAM boost disabled; selected sustained TDP preserved.${NC}"
        else
            echo -e "${YELLOW}[!] HHD is active but QAM boost could not be verified. Check with: hhdctl get tdp.qam.boost${NC}"
        fi

        # The Slide has no charge-limit control. It exposes only a separate
        # binary charge-inhibit backend. Preserve that state: enabling it
        # automatically at a low charge could prevent the next recharge.
        CHARGE_BYPASS=$("$HHDCTL" get tdp.battery.charge_bypass --values --sep='' 2>/dev/null || true)
        if [ "$CHARGE_BYPASS" = always ] || [ "$CHARGE_BYPASS" = disabled ]; then
            echo -e "${GREEN}✓ No percentage charge limit is available; binary bypass state preserved: ${CHARGE_BYPASS}.${NC}"
        else
            echo -e "${YELLOW}[!] HHD charge-bypass state is unavailable; no charging setting was changed.${NC}"
        fi
    else
        echo -e "${YELLOW}[!] HHD is active but hhdctl was not found; QAM boost was not changed.${NC}"
    fi
else
    # CachyOS presets the user unit. Prefer it so only one instance owns the
    # D-Bus name; use the system unit only when no user manager is available.
    systemctl disable --now steamos-manager.service 2>/dev/null || true
    systemctl unmask steamos-manager.service 2>/dev/null || true
    if user_systemctl unmask steamos-manager.service 2>/dev/null && \
       user_systemctl enable --now steamos-manager.service 2>/dev/null; then
        STEAMOS_MANAGER_ACTIVE=user
    else
        systemctl enable --now steamos-manager.service 2>/dev/null || true
        STEAMOS_MANAGER_ACTIVE=system
    fi
    if { [ "$STEAMOS_MANAGER_ACTIVE" = user ] && user_systemctl is-active --quiet steamos-manager.service; } || \
       { [ "$STEAMOS_MANAGER_ACTIVE" = system ] && systemctl is-active --quiet steamos-manager.service; }; then
        echo -e "${YELLOW}[!] HHD unavailable - steamos-manager active as sole power manager. Install HHD before gaming on battery.${NC}"
    else
        echo -e "${RED}[ERROR] Neither HHD nor steamos-manager is active; refusing to leave the system without a power manager.${NC}"
        exit 1
    fi
fi

# 2. Inject verified kernel boot parameters
echo -e "\n${BLUE}[2/6] Configuring Bootloader Parameters...${NC}"
LIMINE_DEFAULT="/etc/default/limine"
BOOT_CONFIGURED=false

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

    # Remember whether the desired APST value predated this run. The
    # normalization below removes every old value before adding one canonical
    # token, but the uninstaller must not remove a value it did not introduce.
    NVME_15000_WAS_PRESENT=false
    if grep -Eq '(^|[[:space:]])nvme_core\.default_ps_max_latency_us=15000([[:space:]\"]|$)' "$LIMINE_DEFAULT"; then
        NVME_15000_WAS_PRESENT=true
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
        if grep -Fq -- "$p" "$LIMINE_DEFAULT"; then
            echo -e "  ${GREEN}✓${NC} $p (already present)"
        else
            sed -i -E "s/(KERNEL_CMDLINE\[default\]\+?=\".*)(\")/\1 $p\2/" "$LIMINE_DEFAULT"
            if grep -Fq -- "$p" "$LIMINE_DEFAULT"; then
                if [ "$p" != "nvme_core.default_ps_max_latency_us=15000" ] || ! $NVME_15000_WAS_PRESENT; then
                    grep -Fxq -- "$p" "$ADDED_PARAMS_FILE" 2>/dev/null || printf '%s\n' "$p" >> "$ADDED_PARAMS_FILE"
                fi
                echo -e "  ${YELLOW}+${NC} Added $p"
            else
                echo -e "${RED}[ERROR] Could not add $p to $LIMINE_DEFAULT.${NC}"
                exit 1
            fi
        fi
    done

    echo -e "  Updating bootloader configuration..."
    limine-update
    BOOT_CONFIGURED=true
    echo -e "${GREEN}✓ Limine bootloader successfully updated.${NC}"
else
    echo -e "${YELLOW}[!] /etc/default/limine not found. Persistent boot configuration was not changed.${NC}"
    echo -e "${YELLOW}    Add these options using your bootloader's documented method:${NC}"
    echo -e "    ${BOLD}${REQUIRED_PARAMS[*]}${NC}"
fi

# 3. Install udev rules (Self-contained heredocs so curl | sudo bash works anywhere)
echo -e "\n${BLUE}[3/6] Installing Udev Rules...${NC}"
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
echo -e "Applied settings:"
echo -e "  1. ${BOLD}Power Management${NC}: HHD TDP/controller, QAM boost off; both steamos-manager units conflict-handled"
echo -e "     ${BOLD}Charging${NC}: percentage limit unsupported; existing binary bypass state preserved"
echo -e "  2. ${BOLD}Suspend Mitigation${NC}: acpi=strict & shallow-only NVMe APST (15000 us)"
echo -e "  3. ${BOLD}CPU Idle Mitigation${NC}: processor.max_cstate=1 & idle=nomwait (A/B test pending)"
echo -e "  4. ${BOLD}iGPU / PCIe Test Baseline${NC}: iommu=pt & pcie_aspm=off"
echo -e "  5. ${BOLD}Display Mitigations${NC}: amdgpu.sg_display=0 & amdgpu.dcdebugmask=0x10 (DCN warning still under test)"
echo -e "  6. ${BOLD}Joystick LED Auto-Off During Sleep${NC}"
echo -e "  7. ${BOLD}NVMe Controller Idle Load Fix${NC}: 15000 us APST ceiling, no I/O cap"
if $BOOT_CONFIGURED; then
    echo -e "\n${YELLOW}Please reboot your system to apply all new kernel parameters:${NC}"
    echo -e "  ${BOLD}sudo systemctl reboot${NC}\n"
else
    echo -e "\n${RED}Runtime fixes are active, but boot parameters are not persistent.${NC}"
    echo -e "${YELLOW}Configure your bootloader before rebooting.${NC}\n"
fi
