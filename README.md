# AYANEO Slide & Antec Core HS - Linux Optimizations & Community Fixes

[![Platform](https://img.shields.io/badge/Platform-CachyOS%20%7C%20Arch-1793D1?logo=arch-linux&logoColor=white)](https://cachyos.org)
[![Hardware](https://img.shields.io/badge/Hardware-AYANEO%20Slide%20%7C%20Antec%20Core%20HS-FF6600)]()
[![APU](https://img.shields.io/badge/APU-AMD%20Ryzen%207%207840U%20%2F%208840U-ED1C24?logo=amd&logoColor=white)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **[English]** | [🇰🇷 **한국어 설명서 (README.ko.md)**](README.ko.md)

A device-specific installer for the **AYANEO Slide** and **Antec Core HS** that applies power-management, controller-conflict, and NVMe idle-temperature mitigations verified on the Ryzen 7 7840U / 8840U platform.

## Why I Built This

Every time I tested another Linux distribution on my AYANEO Slide, I had to hunt down the same kernel options and service-conflict fixes again. Changing distributions should not have meant rediscovering the suspend, controller, TDP, display, and NVMe setup from scratch, so I created this project to keep that work in one reproducible place.

This is not a collection of untested settings copied from the internet. I apply the changes to my **physical AYANEO Slide** and compare boot logs, service state, game launches, download load, SSD power states, and temperatures. The repository packages those results into an installer with a rollback path. When evidence from the device contradicts an earlier explanation, I update both the configuration and the documentation.

> **Why the NVMe setting changed:** `nvme_core.default_ps_max_latency_us=0` was originally an emergency workaround for the Lexar NM7A1 failing to wake after suspend. It disabled all APST states, blocking both the problematic PS4 state and the usable PS3 state. The controller therefore remained operational at idle and measured 68–72°C. The current `15000` setting **continues to exclude PS4 while restoring the 50 mW PS3 state**.

---

## 🎯 Target Devices & Environment

* **Hardware**: AYANEO Slide, Antec Core HS (AMD Ryzen 7 7840U / 8840U, Radeon 780M iGPU, 16GB / 24GB / 32GB LPDDR5X)
* **Storage**: Verified with the OEM Lexar NM7A1 2TB (firmware 9742, Maxio MAP1602, DRAM-less/HMB). Other drives select their own power state within the same 15 ms latency bound
* **Automated install target**: CachyOS Deckify / Arch-based systems with `pacman` and Limine
* **Reference only**: Bazzite, ChimeraOS, SteamOS, GRUB, and systemd-boot users can reuse the documented settings, but the installer does not persist their boot options automatically

---

## 🛠 Issues, Evidence, and Applied Settings

| Issue / Symptom | Observation and assessment | Applied setting |
| :--- | :--- | :--- |
| **Failure to return from suspend** | This was why APST was originally disabled altogether. ACPI behavior and the NM7A1 PS4 resume path are both candidates; the available logs do not isolate one cause. One 15-second `s2idle` cycle passed with the new setting. | **`acpi=strict` + a 15 ms NVMe APST bound**<br>Keeps the community ACPI mitigation and excludes NM7A1 PS4. Repeated and long-duration suspend tests remain outstanding. |
| **Sudden resets / shutdowns** | Affected sessions ended without a clean shutdown, OOM, or NVMe error. The following boot reported `0x00080800`, which records a CF9 software reset and does not identify the root cause by itself. HHD was absent and UMA was 512 MiB during those failures. | **HHD as the only manager + a 12 W device baseline + boost off + `processor.max_cstate=1` + `idle=nomwait`**<br>Avoids competing power managers and deep CPU idle transitions. The installer preserves the selected sustained TDP and disables only QAM boost. UMA is 6 GiB on the tested device. |
| **Lexar NM790 suspend-resume failure and high idle temperature** | The original `default_ps_max_latency_us=0` workaround for resume failures disabled APST entirely and kept the controller active. The NM7A1 reports 5 ms entry + 10 ms exit for PS3, and 8 ms entry + 45 ms exit for PS4. | **`nvme_core.default_ps_max_latency_us=15000`**<br>Continues to exclude deep PS4 while allowing the 50 mW PS3 state. This lowers idle load without an I/O speed cap. PCIe link ASPM remains disabled for platform stability. |
| **Legacy touchscreen-rule cleanup** | A fresh CachyOS Plasma Wayland installation already rotates the native portrait (`1080x1920`) panel and maps touch correctly. Only early versions of this repository added a redundant `LIBINPUT_CALIBRATION_MATRIX`, which caused double rotation. | **No change on a stock installation**<br>The installer only removes the stale `99-ayaneo-slide-touchscreen.rules` left by repository versions before `ae559c0`. |
| **Sleep Battery Drain via Joystick LEDs**<br>*(RGB joystick rings stay on or flash continuously while device is in sleep mode)* | OEM firmware defaults to active blinking during suspend (`[oem] keep off`). | **`udev/99-ayaneo-slide-led-suspend.rules`**<br>Sets `ATTR{suspend_mode}="off"`, automatically cutting power to ring LEDs during sleep. |
| **Clocksource watchdog warning**<br>*(`Watchdog remote CPU read timed out` in older logs)* | The current boot uses TSC and has no clocksource warning, but there is no A/B run proving the old warning came from frequency changes. | **`tsc=reliable` retained as a baseline**<br>This tells the kernel to trust TSC and can suppress watchdog-based fallback; it is a mitigation, not a root-cause fix. |
| **DCN display-buffer warning**<br>*(`REG_WAIT timeout in dcn31_program_compbuf_size`)* | `amdgpu.sg_display=0` is active, but Linux 7.2.3 still logged one timeout during the current boot. There was no GPU reset, and the setting has not passed an A/B dock test. | **Unresolved; `amdgpu.sg_display=0` retained for testing**<br>The repository no longer claims that this option fixes the warning. Repeated dock tests with and without it remain outstanding. |
| **eDP Panel Self Refresh instability**<br>*(Flashes or a black screen during display transitions)* | DCN 3.1.4 eDP PSR transitions can overlap GPU clock changes. | **`amdgpu.dcdebugmask=0x10`**<br>Disables PSR to reduce internal-panel link state changes. |
| **3D / Proton launch stability** | The integrated GPU and NVMe share system-memory bandwidth, so IOMMU translation work can rise during 3D initialization. Available logs do not justify assigning the past resets to one specific hardware error. | **`iommu=pt`**<br>A conservative setting that reduces IOMMU translation overhead for integrated devices. |
| **PCIe link-state transitions** | `pcie_aspm=off` is active and the current read test produced no AER or NVMe errors. No controlled run with ASPM enabled has been completed, so the old voltage-droop explanation is unproven. | **`pcie_aspm=off` retained for testing**<br>Keeps link power-state transitions out of the current stability baseline. An A/B test is still needed, and disabling ASPM can increase idle power. |
| **DRAM-less NVMe HMB use** | The NM7A1 uses host RAM for its mapping cache. It reports both its preferred and minimum HMB size as 8192 pages, and Linux allocates the full request. | **Keep the 32 MiB HMB enabled**<br>Live inspection confirms that all 32 MiB are active. The controller does not request or advertise a larger buffer, and disabling HMB would make address mapping less efficient. |

---

## 🎛️ NVMe Power Management

The installer sets `nvme_core.default_ps_max_latency_us=15000`. From the NM7A1's own power-state descriptors, that 15 ms ceiling includes its 50 mW PS3 state exactly and excludes PS4, whose total transition latency is 53 ms. It enters PS3 after 100 ms without I/O and returns to an operational state when I/O starts, so downloads and game reads have no bandwidth ceiling. `pcie_aspm=off` remains in place for platform link stability while the controller's internal APST is allowed.

The installer removes the legacy `ayaneo-nvme-guard.service` and any `app.slice` write cap. Check APST and HMB state with:

```bash
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
sudo nvme get-feature /dev/nvme0 -f 0x0c -H
sudo nvme get-feature /dev/nvme0 -f 0x0d -H
```

Expected values are `15000`, `APSTE: Enabled`, and `HSIZE: 8192` (32 MiB).

### Measured on the test device (2026-09-15)

| Item | APST fully disabled | After the 15 ms bound |
|---|---:|---:|
| Controller / Composite | 68–72°C | 64–65°C after reboot |
| NAND Sensor 2 | 50–55°C | 52°C |
| Application write cap | 25 MB/s | None |
| Kernel NVMe/AER errors | None | None |

Temperature varies with ambient conditions and recent writes. After a download, internal SLC folding and garbage collection can keep the controller warm even after host writes stop.

A sustained `O_DIRECT` read test held 3.5–3.9 GiB/s without an I/O cap or NVMe/AER error, but raised the controller to 81–82°C. The APST change removes wasted idle and intermittent-load power; it does not eliminate heat while the controller is continuously busy. See [physical-device test results](docs/TEST_RESULTS.md) for passed checks and remaining validation.

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
1. **HHD Ownership**: Keeps one TDP/controller manager, masks both SteamOS Manager instances, preserves the selected sustained TDP, disables QAM boost, and preserves the existing charge-bypass choice.
2. **Safety Backup**: Backs up `/etc/default/limine` to `/etc/default/limine.orig`.
3. **Kernel Parameters**: Appends `acpi=strict`, `processor.max_cstate=1`, `idle=nomwait`, `nvme_core.default_ps_max_latency_us=15000`, `tsc=reliable`, `amdgpu.sg_display=0`, `amdgpu.dcdebugmask=0x10`, `iommu=pt`, and `pcie_aspm=off` to your bootloader. Cleans obsolete/invalid parameters (`amdgpu.gfxoff=0`).
4. **Scheduler Stabilization**: Disables experimental BPF schedulers (`scx_loader`) in favor of upstream Linux EEVDF while recording whether the service was previously enabled for rollback.
5. **Hardware Udev Rules**: Installs the joystick LED suspend auto-off rule. Touchscreen rotation is already handled by the compositor; the installer only removes the obsolete touchscreen rule from early releases of this repository.
6. **Bootloader Rebuild**: Automatically executes `limine-update` to regenerate boot configs and initramfs.
7. **NVMe Power Management**: Updates the live controller PM QoS to 15 ms and removes the legacy `ayaneo-nvme-guard` and `app.slice` write limit.

---

## ↩️ Rollback / Uninstallation

To remove the Limine options, udev rule, and legacy NVMe limiter artifacts installed by this repository, run:

```bash
cd ayaneo-slide-linux-fixes
sudo bash uninstall.sh
sudo systemctl reboot
```

When HHD is still running, the uninstaller keeps HHD and its conflicting-service masks in place so controller and power management are not removed underneath the active session.

Current installs record each Limine option they add, and rollback removes only those recorded options so later user edits survive. A legacy `.orig` file is kept for manual recovery and is never copied wholesale by the uninstaller.

---

## ⚙️ Recommended BIOS Settings

For maximum stability, battery life, and gaming performance, configure the following in BIOS (**Hold Volume (+) or press `Del` repeatedly at boot**):

| Setting | Recommended | Default | Description |
| :--- | :---: | :---: | :--- |
| **UMA Frame buffer Size** | **`6G` tested** | Auto / 3G | Reserves Radeon 780M memory and reduces game VRAM exhaustion while leaving 18 GiB for Linux. It does not guarantee that every game cannot OOM. |
| **fTPM** | **Keep default** | Enabled | The collected logs contain no fTPM error. It may be used for disk encryption or device identity, so change it only if an fTPM-specific stall is reproduced. |
| **Core Watchdog Timer** | **Keep default** | Enabled | The observed CF9 reset record does not prove a watchdog false positive. Do not disable it without an isolated A/B test. |
| **IGD - AmdGop Output Priority** | **`LCD`** | CRT | Sets the internal LCD panel as primary video output, avoiding black-screen bugs on USB-C docks. |

> For in-depth BIOS instructions, see [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md).

---

## 🔋 Recommended Handheld TDP Profiles (Decky Loader)

| Use | TDP | Boost | GPU |
|---|---:|---|---|
| Light games / maximum battery | 8–10 W | Off | Auto |
| **Slide stability starting point** | **12 W** | **Off** | **Auto** |
| General 7840U efficiency target | 15 W | Off | Auto |
| CPU-heavy emulator | 12–15 W | Compare on/off | Auto |

Boost is bounded rather than unlimited. On the observed 8 W profile, enabling it raised HHD's Fast/Slow limits to 10 W while the sustained limit stayed at 8 W; disabling it made all four power limits 8 W. CPU and the Radeon 780M share one package budget, so CPU boost can take power and thermal headroom from the GPU in GPU-limited games. Enable it only when a CPU-heavy workload measurably benefits.

This device currently runs at **12 W with boost off**. Raise it to 15 W only after a 20–30 minute repeat of a workload that previously powered the machine off in about five minutes, such as Space Marine 2. See [TDP, boost, and charge bypass](docs/POWER_AND_CHARGING.md) for the measured behavior and commands.

For demanding games, start with a **30 FPS cap** and use 40 FPS only when the game holds it consistently. A stable cap prevents the APU from spending extra power rendering frames that immediately miss the display target.

## 🔌 No Charge Limit — Bypass Only

This device has **no charge-limit option**. HHD found no `Battery Limit` path, and the firmware exposes no `charge_control_end_threshold`, so an 80% ceiling cannot be configured.

Charge Bypass is a separate binary control with `disabled` and `always` states. HHD maps these to the kernel driver's `auto` and `inhibit-charge` states. This is a manual direct-bypass switch, not a percentage charge limit.

**Normal mode already terminates charging at full capacity.** With HHD `disabled` and kernel `[auto]`, the tested device remained at `capacity=100`, `status=Full`, and `energy_now=energy_full` while `power_now` reported about 0.161 W throughout a 35-second observation. The EC/battery-management system handles normal full-charge termination, so no polling service is needed to prevent charging beyond 100%.

The `ayaneo_platform` driver does not automatically engage direct bypass at a percentage. Its `auto` branch writes the EC value that closes bypass; `inhibit-charge` writes the value that opens bypass. Use `always` only when direct bypass is deliberately wanted at the current charge level.

To hold about 80%, unplug and discharge to 80%, then reconnect with Charge Bypass left on `always`. This inhibits charging at the current level; it does not actively drain a connected battery from 100% to 80%. The installer preserves this choice rather than enabling bypass automatically at an arbitrary battery level.

---

## 🔍 Verification After Installation

To verify the installed settings on your running system:

```bash
# 1. Verify kernel parameters
cat /proc/cmdline
# Expected: ... acpi=strict processor.max_cstate=1 idle=nomwait nvme_core.default_ps_max_latency_us=15000 tsc=reliable

# 2. Verify C-state limitation (only POLL and C1 should be exposed)
ls /sys/devices/system/cpu/cpu0/cpuidle/
# Expected: state0 (POLL) and state1 (C1). C2/C3 states are disabled.

# 3. Verify NVMe power latency
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
# Expected: 15000

# Verify APST is enabled and the NM7A1 targets PS3
sudo nvme get-feature /dev/nvme0 -f 0x0c -H
# Expected: APSTE: Enabled, ITPS: 3

# Verify that the legacy write cap is gone (empty output is expected)
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/io.max

# 4. Verify LED suspend mode
cat /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode
# Expected: [off] oem keep

# 5. Verify HHD TDP, boost, and charge bypass
HHDCTL="$HOME/.local/share/hhd/venv/bin/hhdctl"
"$HHDCTL" get tdp.qam.tdp tdp.qam.boost tdp.battery.charge_bypass
cat /sys/class/power_supply/BAT0/charge_behaviour
# Tested device: 12, false, disabled; kernel: [auto] inhibit-charge
```

---

## 📚 Technical Documentation

* [docs/HARDWARE_ANALYSIS.md](docs/HARDWARE_ANALYSIS.md) — Measured NVMe power states, HMB, temperatures, reset-log evidence, and controller stack analysis.
* [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md) — Reboot, APST, HMB, suspend/resume, direct-read stress results, and known limits.
* [docs/POWER_AND_CHARGING.md](docs/POWER_AND_CHARGING.md) — TDP profiles, boost behavior, the missing percentage charge limit, and the binary bypass control.
* [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) — Step-by-step BIOS tuning guide.
* [README.ko.md](README.ko.md) — 한국어 가이드 및 상세 설명서.

---

## 🔗 Related Projects

* **[Steam Deck & Handheld Korean IME (fcitx5)](https://github.com/jshsakura/steamdeck)** — Battle-tested, zero-click installer for Korean input on Steam Deck, AYANEO Slide, and Linux handhelds (features Right-Alt Hangul mapping and gaming-safe shortcuts).

---

## 🤝 Acknowledgements & References

* [ChimeraOS Issue #892](https://github.com/ChimeraOS/chimeraos/issues/892) — For uncovering the `acpi=strict` breakthrough for AYANEO Slide / Antec Core HS.
* [Valve Software SteamOS Issue #2757](https://github.com/ValveSoftware/SteamOS/issues/2757) — Community investigation of AMD platform resets.
* [Bazzite Issue #5596 & #5508](https://github.com/ublue-os/bazzite/issues/5596) — Handheld sleep state and input mapping investigations.
* [ShadowBlip / ayaneo-platform](https://github.com/ShadowBlip/ayaneo-platform) — Linux kernel platform driver for AYANEO devices.

---

## 📜 License

Released under the [MIT License](LICENSE). Contributions, bug reports, and PRs are welcome!
