# AYANEO Slide Linux Hardware Observations and Mitigations

This document records the hardware data and logs observed on the test device. It separates measured facts from conservative mitigations; a reset code alone is not treated as proof of a root cause.

## Test device

- AYANEO Slide, AMD Ryzen 7 7840U / Radeon 780M
- 24 GiB LPDDR5X, UMA frame buffer set to 6 GiB
- Lexar SSD NM7A1 2TB, firmware 9742, Maxio MAP1602 (`1d97`), DRAM-less
- CachyOS Deckify, Linux `7.2.3-1-cachyos-deckify`
- HHD active at 12 W with TDP boost disabled and charge bypass set to `always`

## NVMe controller power and temperature

`nvme id ctrl -H` reports five power states for the NM7A1:

| State | Type | Maximum power | Entry | Exit | Total latency |
|---|---|---:|---:|---:|---:|
| PS0 | operational | 6.50 W | 0 | 0 | 0 |
| PS1 | operational | 5.80 W | 0 | 0 | 0 |
| PS2 | operational | 3.60 W | 0 | 0 | 0 |
| PS3 | non-operational | 50 mW | 5 ms | 10 ms | 15 ms |
| PS4 | non-operational | 2.5 mW | 8 ms | 45 ms | 53 ms |

The old setting `nvme_core.default_ps_max_latency_us=0` was added as an emergency workaround for the drive failing to return after system suspend. It prevented the suspected deep PS4 resume path by disabling APST completely. Live NVMe feature data confirmed `APSTE: Disabled`, which also prevented the lower-latency PS3 state even when host I/O stopped. Together with `pcie_aspm=off`, this explained why the controller stayed warm while the desktop appeared idle.

The current setting is:

```text
nvme_core.default_ps_max_latency_us=15000
```

Linux now programs a 100 ms idle timeout to PS3 and leaves the PS4 entries unused. This retains the original workaround's essential property—never entering PS4—without forcing the controller to stay operational. The PCIe link itself remains in the conservative `pcie_aspm=off` configuration.

Measured snapshots on 2026-09-15:

| Configuration | Controller / Composite | NAND Sensor 2 | Application write cap |
|---|---:|---:|---:|
| APST disabled | 68–72°C | 50–55°C | 25 MB/s legacy cap |
| 15 ms APST bound, after reboot | 64–65°C | 52°C | none |

These are snapshots, not a controlled thermal benchmark. Ambient temperature and recent writes matter. A DRAM-less drive can continue SLC folding and garbage collection after host write traffic falls, so temperature may lag behind the visible workload.

## Host Memory Buffer

The controller reports `hmpre=8192` and `hmmin=8192`, and Linux allocates `32 MiB host memory buffer (8 segments)`. NVMe feature `0x0d` reports HMB enabled with `HSIZE: 8192`.

The full controller-requested HMB is already assigned. The device does not advertise a larger preferred buffer, and adding arbitrary system RAM would not make the controller use it. HMB is a mapping cache; it does not replace the controller's internal execution resources or solve active-state power use.

## I/O limiting

The previous installer wrote a 25 MB/s limit to the user session's `app.slice`. That reduced sustained write heat but did not address idle controller power, read-heavy games, or internal maintenance. It also slowed legitimate downloads.

The current installer removes `ayaneo-nvme-guard.service`, clears legacy cgroup limits, and does not install another bandwidth throttle. The current `app.slice/io.max` is empty.

## Reset evidence and power management

Two Space Marine 2 sessions ended after several minutes with an abrupt journal boundary and no clean game exit, orderly shutdown, OOM kill, amdgpu reset, NVMe timeout, or media error. HHD was not installed during those failures and UMA was 512 MiB.

The next boot reported `[0x00080800]: software wrote 0x6 to reset control register 0xCF9`. The same value can appear after an ordinary software reboot, so it does not prove a Data Fabric Sync Flood. Claims that the observed value was `0x08000800` were removed from this repository.

The installed mitigations remain conservative:

- HHD is the sole TDP/controller manager; both system and user `steamos-manager` units are masked while HHD is active. The current driver stack exposes no PWM-controllable fan to HHD.
- The current stability baseline is 12 W with boost disabled and GPU frequency on auto. The installer preserves the user's sustained HHD TDP but disables QAM boost.
- HHD boost is bounded. At the observed 8 W setting, enabling it raised Fast/Slow to 10 W while Skin/STAPM remained 8 W; disabling it made all four limits 8 W. At the current 12 W setting with boost disabled, all four limits are 12 W.
- `processor.max_cstate=1` and `idle=nomwait` avoid deep CPU idle transitions. They can increase APU and chassis idle power, so they remain candidates for an isolated A/B test rather than proven reset fixes.
- `scx_loader` is disabled in favor of the kernel's standard scheduler.
- `tsc=reliable` keeps TSC selected on this configuration. It can suppress watchdog-based fallback and has not been isolated as the cause of the historical warning.

These settings reduce variables and power transients. They do not turn the reset record into proof of one hardware failure mode.

## No battery charge limit; bypass backend only

HHD's probe found `/sys/class/power_supply/BAT0/charge_behaviour` for `Battery Bypass` but printed no path for `Battery Limit`. The kernel exposes neither `charge_control_start_threshold` nor `charge_control_end_threshold`, so the device has no programmable 80% charge-limit option.

The separate bypass backend reports `tdp.battery.charge_bypass=always`, and the battery power-supply interface reports `auto [inhibit-charge]`. Its only backend states are `disabled` and `always`; these are not percentage choices.

The available control inhibits charging at the present state of charge. It does not command a connected battery to discharge from 100% to 80%. Linux can confirm the inhibit state but does not expose internal rail telemetry that would independently prove hardware-level direct bypass.

The installer uses a 30-second systemd timer with hysteresis: it selects `always` at a reported capacity of 100%, keeps the existing state from 96–99%, and selects `disabled` at 95% or below. The helper reads the selected kernel `charge_behaviour` state and exits without calling HHD when it already matches. See [POWER_AND_CHARGING.md](POWER_AND_CHARGING.md).

## GPU, display, and PCIe mitigations

- `iommu=pt` reduces translation overhead for integrated devices.
- `amdgpu.sg_display=0` is active, but the current Linux 7.2.3 boot still logged one `REG_WAIT timeout` in `dcn31_program_compbuf_size`. There was no GPU reset. This setting is retained for an A/B dock test and is not considered a verified fix.
- `amdgpu.dcdebugmask=0x10` disables panel self refresh on the internal eDP panel.
- `pcie_aspm=off` keeps PCIe link-level low-power transitions disabled. NVMe APST remains independently active with the 15 ms bound. No ASPM-on A/B run has been completed, so this remains part of the test baseline rather than a verified fix; it can also increase idle power.
- GPU DPM stays on `auto`; the installer removes the old udev rule that forced `high` performance.

These are platform-stability mitigations. The repository does not claim that each setting independently fixes a specific reset without a reproducible A/B test.

## Controller stack

HHD has device support for the AYANEO Slide and owns the physical controller, gyro, back buttons, and emulated gamepad. Running InputPlumber at the same time caused repeated `Device or resource busy` failures while both stacks tried to own controller emulation.

The installer therefore masks `inputplumber` when HHD is active. If HHD cannot start, it keeps InputPlumber available instead of leaving the machine without a controller layer. It masks both the system and user `steamos-manager` units because the user unit remains D-Bus activatable even when the system unit is masked. Without HHD, it restores one SteamOS Manager instance rather than starting both.

## Verification

After reboot, the expected state is:

```bash
cat /proc/cmdline
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
cat /sys/class/nvme/nvme0/power/pm_qos_latency_tolerance_us
sudo nvme get-feature /dev/nvme0 -f 0x0c -H
sudo nvme get-feature /dev/nvme0 -f 0x0d -H
systemctl is-active ayaneo-nvme-guard.service
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/io.max
"$HOME/.local/share/hhd/venv/bin/hhdctl" get tdp.qam.tdp tdp.qam.boost tdp.battery.charge_bypass
cat /sys/class/power_supply/BAT0/charge_behaviour
systemctl status ayaneo-charge-at-full.timer --no-pager
```

The command line, module parameter, and device QoS should show `15000`; APST should be enabled with PS3 as the idle target; HMB should show `HSIZE: 8192`; the legacy guard should be inactive or absent; and `io.max` should be empty. The current device reports TDP 12, boost `false`, charge bypass `always`, and kernel charge behavior `inhibit-charge`.
