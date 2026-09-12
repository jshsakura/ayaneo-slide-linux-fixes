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
