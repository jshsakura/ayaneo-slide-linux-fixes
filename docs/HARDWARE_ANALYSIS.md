# AYANEO Slide Linux Hardware Analysis & Chronic Bug Root Causes

This document details the root causes and technical resolutions for known hardware issues encountered on the **AYANEO Slide** (AMD Ryzen 7 7840U Phoenix APU, Lexar NM790 / Maxio MAP1602 DRAM-less NVMe SSD).

---

## 1. Sleep/Wake Freeze (Blackout on `s2idle` Suspend)

### Symptoms
* Pressing the power button enters suspend (`PM: suspend entry (s2idle)`).
* The screen turns black or dimmed, but the device never wakes up from suspend.
* Power button and gamepad buttons are unresponsive, forcing a hard reset.

### Root Cause
1. **AMI BIOS ACPI DSDT Bug**:
   The AYANEO Slide BIOS ACPI tables contain non-standard power management routines. Without strict ACPI parsing, the Linux kernel power manager attempts invalid device sleep transitions, causing a kernel deadlock upon entering or resuming `s2idle`.
2. **Lexar NM790 / Maxio MAP1602 APST Controller Failure**:
   The Lexar NM790 NVMe SSD uses the Maxio MAP1602 DRAM-less controller (`1d97:1602`). On Linux, this controller fails to exit deep APST PS4 power state, dropping off the PCIe bus and deadlocking root filesystem I/O.

### Solution
* `acpi=strict`: Forces the kernel to enforce strict ACPI compliance, bypassing buggy OEM DSDT routines (proven fix from ChimeraOS Issue #892).
* `nvme_core.default_ps_max_latency_us=0`: Restricts the NVMe SSD from entering deep latency sleep states, keeping the controller active.

---

## 2. Spontaneous Sudden Reboots & Data Fabric Sync Flood (`0x08000800`)

### Symptoms
* Device suddenly resets and reboots while idle, in the Steam menu, or shortly after booting.
* Kernel log after reboot reports:
  ```text
  x86/amd: Previous system reset reason [0x08000800]: an uncorrected error caused a data fabric sync flood event
  clocksource: Watchdog remote CPU read timed out
  ```

### Root Cause
1. **Zen 4 Low-Power C-State Voltage Droop**:
   When CPU cores drop into deep C-states (C2/C3) during low load or idle, the SoC and core voltages drop. Upon waking, transient voltage droop across the power delivery circuitry causes an uncorrectable communication error in the AMD Infinity Fabric (Data Fabric). The CPU die hardware asserts an emergency **Sync Flood (0x08000800)** to prevent memory corruption.
2. **Unstable BPF CPU Schedulers (`scx_lavd`)**:
   Experimental schedulers stall remote CPU cores during idle power transitions, accelerating watchdog timeouts and fabric sync floods.

### Solution
* `processor.max_cstate=1` + `idle=nomwait`: Limits CPU idle states to C1, preventing the voltage from dropping into the unstable C2/C3 droop threshold.
* Disable `scx_loader.service`: Reverts to the stable upstream Linux EEVDF scheduler.
* `tsc=reliable`: Prevents clocksource watchdog timeouts.

---

## 3. Gamepad Device Hiding & InputPlumber Architecture

### Architecture
* Physical Controller: ZhiXu Controller (`045e:028e`) on internal USB bus (`1-3`).
* InputPlumber intercepts the raw controller and sets mode `0000` (`c---------`) via udev rules to **hide** the raw device from games, preventing double-input bugs.
* InputPlumber creates a virtual Steam Deck controller (`deck-uhid`, `28de:12f0`), which Steam picks up via `hidraw` and maps cleanly to `configset_controller_steamos_handheld`.

---

## 4. DCN 3.1.4 HUBBUB Lockup on Multi-Display / Docking

### Symptoms
* Kernel warnings upon connecting USB-C docks or external 4K displays:
  ```text
  amdgpu 0000:c4:00.0: [drm] REG_WAIT timeout 1us * 100 tries - dcn31_program_compbuf_size line:141
  WARNING: at dcn31_hubbub.c:151 at dcn31_program_compbuf_size [amdgpu]
  ```
* Sudden hard reset (`[0x08000800] Data Fabric Sync Flood`) triggered when Steam, Gamescope, or 3D Vulkan applications launch with external displays connected.

### Root Cause
1. **DCN 3.1.4 HUBBUB Scatter-Gather Allocation**:
   When external docks or 4K monitors (`DP-2`) are plugged in alongside the internal portrait screen (`eDP-1`), KWin Wayland triggers display bandwidth optimization (`dcn20_optimize_bandwidth`). The DCN 3.1.4 HUBBUB compression buffer controller attempts to dynamically resize memory segments over non-contiguous Scatter-Gather (SG) system RAM buffers and hits a register timeout (`REG_WAIT timeout`). This leaves the memory arbiter on the Data Fabric in an unstable deadlock state, causing an emergency Sync Flood reset when heavy graphics contexts (Steam) request VRAM buffers.

### Solution
* `amdgpu.sg_display=0`: Disables Scatter-Gather display buffer allocations on the APU, forcing contiguous dedicated VRAM for display buffers and completely eliminating HUBBUB compression buffer register timeouts.

---

## 5. 3D / Proton Launch Data Fabric Sync Flood & IOMMU Overhead

### Symptoms
* Launching a 3D game (Vulkan/Proton) immediately causes an instant hard reboot.
* Previous reset reason is recorded as:
  ```text
  x86/amd: Previous system reset reason [0x08000800]: an uncorrected error caused a data fabric sync flood event
  ```

### Root Cause
On AMD Phoenix APUs (Ryzen 7 7840U / 8840U), the CPU and Radeon 780M iGPU share a unified memory controller over the AMD Infinity Fabric. When 3D engines initialize and allocate large VRAM slabs via DMA, the kernel's default dynamic IOMMU DMA translation table walk generates micro-stalls and bus contention on the Data Fabric. Under burst load, these stalls escalate into an uncorrectable fabric timeout.

### Solution
* `iommu=pt`: Sets IOMMU to Passthrough mode for integrated APU DMA devices. This eliminates address translation overhead and translation table walk stalls, allowing direct zero-latency DMA between the iGPU and unified RAM.

---

## 6. PCIe Power State Transition Droop on NVMe & Root Complex

### Symptoms
* Device freezes or resets under sustained heavy NVMe disk writes (such as Steam game downloads, updates, or decompression).
* Controller timeout or ACPI power state transition errors (`[0x00200800]`).

### Root Cause
Active State Power Management (ASPM) commands PCIe devices to enter lower power states (L0s/L1) during micro-idle intervals. The DRAM-less Lexar NM790 (Maxio MAP1602 controller) and the APU internal PCIe bridges experience significant latency and voltage droop when rapidly switching back to active L0.

### Solution
* `pcie_aspm=off`: Completely disables PCIe ASPM, forcing PCIe links to remain in full-power active mode (L0) at all times, preventing bus drops and voltage transients.

---

## 7. eDP Panel Self Refresh (PSR) Instability

### Symptoms
* Screen flashes white or goes black under GPU clock shifts or when switching between desktop and full-screen games.

### Root Cause
DCN 3.1.4 PSR power-state transitions on the eDP panel conflict with rapid APU clock scaling.

### Solution
* `amdgpu.dcdebugmask=0x10`: Completely disables Panel Self Refresh, keeping the display link continuously clocked and eliminating fabric sync floods during display mode changes.

