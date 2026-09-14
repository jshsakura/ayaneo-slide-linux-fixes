# AYANEO Slide & Antec Core HS - Linux Optimizations & Community Fixes

[![Platform](https://img.shields.io/badge/Platform-CachyOS%20%7C%20Arch%20%7C%20Bazzite%20%7C%20SteamOS-1793D1?logo=arch-linux&logoColor=white)](https://cachyos.org)
[![Hardware](https://img.shields.io/badge/Hardware-AYANEO%20Slide%20%7C%20Antec%20Core%20HS-FF6600)]()
[![APU](https://img.shields.io/badge/APU-AMD%20Ryzen%207%207840U%20%2F%208840U-ED1C24?logo=amd&logoColor=white)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **[English]** | [🇰🇷 **한국어 설명서 (README.ko.md)**](README.ko.md)

A battle-tested, community-verified optimization suite that eliminates all chronic hardware bugs, sleep/wake deadlocks, and spontaneous reboots on the **AYANEO Slide** (and its twin, the **Antec Core HS**), powered by the AMD Ryzen 7 7840U / 8840U Phoenix APU.

---

## 🎯 Target Devices & Environment

* **Hardware**: AYANEO Slide, Antec Core HS (AMD Ryzen 7 7840U / 8840U, Radeon 780M iGPU, 16GB / 24GB / 32GB LPDDR5X)
* **Storage**: Compatible with all NVMe drives, including the OEM **Lexar NM7A1 (DRAM-less, Host Memory Buffer)**
* **Supported Distros**: CachyOS (Handheld Edition), Arch Linux, Bazzite, ChimeraOS, SteamOS (SteamFork)
* **Bootloaders**: Limine (default on CachyOS Deckify), GRUB, systemd-boot

---

## 🛠 Chronic Issues & Applied Resolutions

| Issue / Symptom | Root Cause | Solution Applied |
| :--- | :--- | :--- |
| **Sleep/Wake Blackout Freeze**<br>*(Device goes to sleep via power button, screen stays black/dim, never wakes up)* | AMI BIOS ACPI DSDT implementation contains non-standard OEM power routines that cause Linux kernel power manager lockup during `s2idle`. | **`acpi=strict`**<br>Enforces strict ACPI compliance, bypassing buggy OEM routines (*proven fix from ChimeraOS Issue #892*). |
| **Spontaneous Hard Resets / Sync Flood**<br>*(Sudden instant reboot during idle or menu, reset reason `[0x08000800]`; on battery, heavy 3D game load cuts power off entirely)* | ① Zen 4 C3 deep idle states cause transient voltage droops - on wake, an uncorrectable interconnect parity error triggers AMD Data Fabric Sync Flood. ② **Without TDP limits, 3D transients trip the 46Wh BMS into instant hard power-off** (power cut, not a reboot; happens on battery). | **`processor.max_cstate=1`** & **`idle=nomwait`** + **HHD (Handheld Daemon) required**<br>Restricts idle transitions to stable C1. HHD provides TDP/fan management with official AYANEO Slide support; the installer auto-installs it and masks the conflicting `steamos-manager` (plain disable is bypassed by Steam's D-Bus activation). Also disables unstable BPF schedulers (`scx_loader`). |
| **Lexar NM790 high idle temperature and deep-sleep instability** | `default_ps_max_latency_us=0` disables APST entirely and keeps the controller active. The NM7A1 reports 5 ms entry + 10 ms exit for PS3, and 8 ms entry + 45 ms exit for PS4. | **`nvme_core.default_ps_max_latency_us=15000`**<br>Allows the 50 mW PS3 state while excluding the deepest 2.5 mW PS4 state. This lowers idle load without an I/O speed cap. PCIe link ASPM remains disabled for platform stability. |
| **Touchscreen Registers in Wrong Places (Double Rotation)**<br>*(Touches land in rotated/mirrored positions instead of where you tapped)* | The native panel is portrait (`1080x1920`); KWin (Plasma Wayland) already applies the 90-degree output transform to touch coordinates. An additional udev `LIBINPUT_CALIBRATION_MATRIX` rotates them a second time, landing touches off-target. | **No calibration matrix**<br>Compositors handle the rotation natively, so the old `99-ayaneo-slide-touchscreen.rules` was removed. |
| **Sleep Battery Drain via Joystick LEDs**<br>*(RGB joystick rings stay on or flash continuously while device is in sleep mode)* | OEM firmware defaults to active blinking during suspend (`[oem] keep off`). | **`udev/99-ayaneo-slide-led-suspend.rules`**<br>Sets `ATTR{suspend_mode}="off"`, automatically cutting power to ring LEDs during sleep. |
| **Clocksource Watchdog Timeouts**<br>*(Kernel logs `Watchdog remote CPU read timed out` on core frequency changes)* | Variable TSC frequency shifts during APU governor changes. | **`tsc=reliable`**<br>Marks invariant TSC as a reliable clocksource across all 16 APU threads. |
 | **DCN Hubbub Lockup on Dock / External Display**<br>*(Kernel warning `REG_WAIT timeout in dcn31_program_compbuf_size` when plugging in USB-C dock or changing resolution)* | DCN 3.1.4 display compression buffer arbiter locks up on the Data Fabric during Scatter-Gather DMA reallocations. | **`amdgpu.sg_display=0`**<br>Disables non-contiguous Scatter-Gather display buffer allocations on APU, using dedicated VRAM to guarantee DCHUBBUB stability. |
| **eDP Panel Self Refresh (PSR) Instability**<br>*(Intermittent data fabric sync flood resets under GPU load — e.g. Steam launch or Proton prefix setup)* | DCN 3.1.4 PSR power-state transitions on the eDP panel destabilize the display pipeline and the Data Fabric on Phoenix APUs. | **`amdgpu.dcdebugmask=0x10`**<br>Disables PSR, keeping the eDP link active to avoid fabric-level faults during GPU clock transitions. |
| **3D / Proton Launch Fabric Sync Flood**<br>*(Hard reboot with reset reason `[0x08000800]` when Proton/Vulkan initializes 3D graphics)* | IOMMU dynamic DMA address translation table walks introduce stalls on APU unified memory interconnect under burst graphics memory requests. | **`iommu=pt`**<br>Sets IOMMU to Passthrough mode for integrated APU DMA, bypassing address translation overhead and memory controller stalls. |
| **PCIe Link Voltage / Latency Droop Under Load**<br>*(Sudden resets or device drops during sustained disk I/O or power transitions)* | PCIe Active State Power Management (ASPM) causes link latency and voltage fluctuations on DRAM-less NVMe controllers and internal bridges. | **`pcie_aspm=off`**<br>Disables PCIe ASPM power saving states, ensuring continuous high-speed signal integrity under load. |
| **DRAM-less NVMe HMB use** | The NM7A1 uses host RAM for its mapping cache. It reports both its preferred and minimum HMB size as 8192 pages, and Linux allocates the full request. | **Keep the 32 MiB HMB enabled**<br>Live inspection confirms that all 32 MiB are active. The controller does not request or advertise a larger buffer, and disabling HMB would make address mapping less efficient. |

---

## 🎛️ NVMe Power Management

The installer sets `nvme_core.default_ps_max_latency_us=15000`. From the NM7A1's own power-state descriptors, that 15 ms ceiling includes its 50 mW PS3 state exactly and excludes PS4, whose total transition latency is 53 ms. Active I/O returns immediately to an operational state, so downloads and game reads have no bandwidth ceiling.

The installer removes the legacy `ayaneo-nvme-guard.service` and any `app.slice` write cap. Check APST and HMB state with:

```bash
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
sudo nvme get-feature /dev/nvme0 -f 0x0c -H
sudo nvme get-feature /dev/nvme0 -f 0x0d -H
```

Expected values are `15000`, `APSTE: Enabled`, and `HSIZE: 8192` (32 MiB).

---

## 🚀 Quick Installation (One-Liner)

Open a terminal (e.g., Konsole in Desktop Mode) and run this single command:

```bash
curl -sSL https://raw.githubusercontent.com/jshsakura/ayaneo-slide-linux-fixes/main/install.sh | sudo bash
```

Once the installation completes, reboot your device to activate all kernel parameters:

```bash
sudo systemctl reboot
```

<details>
<summary><b>Alternative: Manual Git Clone</b></summary>

```bash
git clone https://github.com/jshsakura/ayaneo-slide-linux-fixes.git
cd ayaneo-slide-linux-fixes
sudo bash install.sh
sudo systemctl reboot
```
</details>

### What `install.sh` Does:
1. **Safety Backup**: Backs up `/etc/default/limine` to `/etc/default/limine.orig`.
2. **Kernel Parameters**: Appends `acpi=strict`, `processor.max_cstate=1`, `idle=nomwait`, `nvme_core.default_ps_max_latency_us=15000`, `tsc=reliable`, `amdgpu.sg_display=0`, `amdgpu.dcdebugmask=0x10`, `iommu=pt`, and `pcie_aspm=off` to your bootloader. Cleans obsolete/invalid parameters (`amdgpu.gfxoff=0`).
3. **Scheduler Stabilization**: Permanently disables experimental BPF schedulers (`scx_loader`) in favor of upstream Linux EEVDF.
4. **Hardware Udev Rules**: Installs the joystick LED suspend auto-off rule. (Touchscreen landscape rotation is handled natively by the compositor, so no calibration rule is installed.)
5. **Bootloader Rebuild**: Automatically executes `limine-update` to regenerate boot configs and initramfs.

---

## ↩️ Rollback / Uninstallation

If you ever wish to revert all changes back to clean factory state:

```bash
cd ayaneo-slide-linux-fixes
sudo bash uninstall.sh
sudo systemctl reboot
```

---

## ⚙️ Recommended BIOS Settings

For maximum stability, battery life, and gaming performance, configure the following in BIOS (**Hold Volume (+) or press `Del` repeatedly at boot**):

| Setting | Recommended | Default | Description |
| :--- | :---: | :---: | :--- |
| **UMA Frame buffer Size** | **`6G`** or **`8G`** | Auto / 3G | Allocates fixed VRAM to Radeon 780M. Completely prevents Out-Of-Memory (OOM) crashes in modern AAA games (*Slide has 24GB RAM*). |
| **fTPM** | **`Disabled`** | Enabled | Eliminates intermittent micro-stuttering and frame hitching known across AMD Zen 4 mobile APUs on Linux. |
| **Core Watchdog Timer** | **`Disabled`** | Enabled | Prevents unintended hardware-level reboots caused by false-positive core watchdog stalls. |
| **IGD - AmdGop Output Priority** | **`LCD`** | CRT | Sets the internal LCD panel as primary video output, avoiding black-screen bugs on USB-C docks. |

> For in-depth BIOS instructions, see [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md).

---

## 🔋 Recommended Handheld TDP Profiles (Decky Loader)

Install **SimpleDeckyTDP** or **PowerTools** via Decky Loader for real-time power capping in Steam Game Mode:

* **On Battery**: Set TDP to **`15W – 18W`**
  * The 7840U sweet spot for perf-per-watt. Prevents BMS overcurrent voltage cutoffs on the Slide's 46Wh battery while offering 1.5 to 2.5 hours of AAA gameplay.
* **On AC Power (Docked)**: Set TDP to **`22W – 28W`**
* **Manual GPU Clock**: Pin between **`1200MHz – 1600MHz`** to stabilize 1% low frame times and eliminate CPU/GPU power throttling.

---

## 🔍 Verification After Installation

To verify that all fixes are active on your running system:

```bash
# 1. Verify kernel parameters
cat /proc/cmdline
# Expected: ... acpi=strict processor.max_cstate=1 idle=nomwait nvme_core.default_ps_max_latency_us=15000 tsc=reliable

# 2. Verify C-state limitation (only POLL and C1 should be active)
ls /sys/devices/system/cpu/cpu0/cpuidle/
# Expected: state0 (POLL) and state1 (C1). C2/C3 states are disabled.

# 3. Verify NVMe power latency
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
# Expected: 15000

# 4. Verify LED suspend mode
cat /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode
# Expected: [off] oem keep
```

---

## 📚 Technical Documentation

* [docs/HARDWARE_ANALYSIS.md](docs/HARDWARE_ANALYSIS.md) — Comprehensive technical deep-dive into the Data Fabric Sync Flood (`0x08000800`), ACPI DSDT lockup, and controller hiding mechanism.
* [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) — Step-by-step BIOS tuning guide.
* [README.ko.md](README.ko.md) — 한국어 가이드 및 상세 설명서.

---

## 🔗 Related Projects

* **[Steam Deck & Handheld Korean IME (fcitx5)](https://github.com/jshsakura/steamdeck)** — Battle-tested, zero-click installer for Korean input on Steam Deck, AYANEO Slide, and Linux handhelds (features Right-Alt Hangul mapping and gaming-safe shortcuts).

---

## 🤝 Acknowledgements & References

* [ChimeraOS Issue #892](https://github.com/ChimeraOS/chimeraos/issues/892) — For uncovering the `acpi=strict` breakthrough for AYANEO Slide / Antec Core HS.
* [Valve Software SteamOS Issue #2757](https://github.com/ValveSoftware/SteamOS/issues/2757) — Research into AMD Zen 4 Data Fabric Sync Flood hardware resets.
* [Bazzite Issue #5596 & #5508](https://github.com/ublue-os/bazzite/issues/5596) — Handheld sleep state and input mapping investigations.
* [ShadowBlip / ayaneo-platform](https://github.com/ShadowBlip/ayaneo-platform) — Linux kernel platform driver for AYANEO devices.

---

## 📜 License

Released under the [MIT License](LICENSE). Contributions, bug reports, and PRs are welcome!
