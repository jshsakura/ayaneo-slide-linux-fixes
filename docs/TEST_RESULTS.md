# Test Results and Known Limits

Tested on the author's physical AYANEO Slide on 2026-09-15, with follow-up inspection on 2026-09-16. These results describe this device and software build; they are not universal guarantees for every SSD firmware or distribution.

## Configuration

- CachyOS Deckify, Linux `7.2.3-1-cachyos-deckify`
- Lexar SSD NM7A1 2TB, firmware 9742
- `nvme_core.default_ps_max_latency_us=15000`
- `pcie_aspm=off`
- 32 MiB HMB
- HHD 4.1.12

## Passed checks

| Check | Result | Evidence |
|---|---|---|
| Persistent boot option | Pass | `/proc/cmdline`, module parameter, and NVMe device QoS all reported `15000` after reboot |
| Post-reboot observation | Pass, 16 h 57 min | The same boot ID remained active through 2026-09-16 00:14 KST with no NVMe/AER error, GPU reset, OOM, MCE, or unexpected reboot |
| APST selection | Pass | APSTE enabled; PS0–PS2 transition to PS3 after 100 ms; PS4 entries unused |
| HMB allocation | Pass | Kernel allocated 32 MiB in 8 segments; feature `0x0d` reported `HSIZE: 8192` |
| Legacy limiter removal | Pass | `ayaneo-nvme-guard.service` inactive/absent and user `app.slice/io.max` empty |
| Idle temperature snapshot | Pass | Controller/Composite settled to 57.9°C and NAND Sensor 2 to 47.9°C; the first post-reboot samples were 64–65°C/52°C and old APST-off snapshots were 68–72°C |
| Timed suspend/resume | Pass, 1 cycle | 15-second `s2idle` cycle returned with the same boot ID; APST remained enabled with PS3 and QoS 15000; no NVMe or AER error |
| Direct-read stress | Pass | 40 seconds of `O_DIRECT` sequential reads sustained 3.5–3.9 GiB/s with no NVMe/AER error |
| Script static checks | Pass | `bash -n` and `git diff --check`; the Limine fixture produced one `default_ps_max_latency_us=15000` argument, and the rollback fixture removed tracked options while preserving an unrelated later option |
| Service conflict isolation | Pass after fix | Both system and user SteamOS Manager units are masked while HHD is active; no failed user units remain |
| HHD boost state | Pass after fix | At 8 W, boost on produced 10 W Fast/Slow and 8 W Skin/STAPM; boost off made all four 8 W. The current 12 W boost-off profile reports all four at 12 W |
| Charge bypass capability | Pass, binary only | HHD reported `always` and Linux reported `auto [inhibit-charge]`; no start/end percentage-threshold files exist |
| DCN `REG_WAIT` warning | **Not resolved** | `amdgpu.sg_display=0` and `amdgpu.dcdebugmask=0x10` were active, but one `dcn31_program_compbuf_size` timeout still appeared during boot; no GPU reset followed |

## Thermal limit observed under load

The direct-read test raised the controller from about 64°C to 81–82°C while NAND reached 59°C. This is below the drive's reported 90°C warning and 95°C critical thresholds, but it confirms that shallow APST only reduces idle and intermittent-workload power. It cannot cool a controller that is continuously processing several GiB/s.

The repository intentionally does not restore the old bandwidth limiter. Sustained-load temperature must be handled by the drive's own thermal policy, chassis cooling, or a hardware change. After the read load stopped, the controller fell to 71–73°C during the following samples.

## Suspend observations

The tested `s2idle` cycle completed and the NVMe controller recreated its eight I/O queues. HHD briefly observed the physical controller disconnect during suspend, cached it, and recreated the emulated controller within about 0.3 seconds. Its daemon remained active.

The `\_SB.ALIB` method returns `AE_AML_NO_RETURN_VALUE` whenever HHD writes the limits, at boot as well as after resume. The HHD API reports `tdp.smu.status=Set` and continues running; after boost was disabled, its state reported fast/slow/skin/STAPM all at 8 W. This shows that HHD accepted and retained the requested state, but the current interfaces do not expose an independent hardware readback of the SMU registers. Longer suspend duration and repeated overnight cycles have not yet been validated.

The kernel also reported that the BIOS was not configured for optimal suspend-to-idle power consumption. Wake worked, but this warning means the test does not establish low battery drain during suspend.

The display options have not passed dock A/B testing. The current boot log disproves the earlier claim that `amdgpu.sg_display=0` eliminates the DCN timeout.

## Power and charging observations

The current profile is 12 W with QAM TDP boost disabled, GPU frequency management on auto, and Fast/Slow/Skin/STAPM limits all at 12 W. The earlier 8 W boost-on profile raised only the bounded Fast/Slow limits to 10 W, so boost did not remove the power ceiling.

HHD exposes Charge Bypass as `disabled` or `always`; it does not offer a percentage. With `always` selected at 100%, `/sys/class/power_supply/BAT0/charge_behaviour` showed `auto [inhibit-charge]`. No `charge_control_start_threshold` or `charge_control_end_threshold` exists. Holding about 80% therefore requires discharging to that level before reconnecting with bypass enabled. Persistence across a later reboot and the actual battery current at 80% still need measurement.

## Other observed warnings

- HHD reported no PWM-controllable fan. On this software stack it manages TDP and the controller, not the fan.
- The HHD overlay AppImage dumped core once during its `--version` probe and later exited when the gamescope display connection closed. The core HHD daemon, TDP path, and emulated controller remained active. This is an upstream overlay issue, not an NVMe failure.
- `/usr/lib/udev/rules.d/70-led-control.rules` attempts to `chown` LED attributes that `xpad0` does not provide, producing harmless udev worker failures after resume. The rule is distribution-owned and is not installed by this repository.
- The system exposes only `BAT0` and no separate AC supply node, so HHD logged that it could not find an AC-status file. Do not assume automatic AC/battery TDP switching on this device.
- `gamescope-wl` aborted once in `libseat` while the short gamescope session was being stopped, and the HHD overlay exited with that display connection. The desktop session and core HHD daemon stayed available; this was not a whole-device reset.
- Three static units from `gamescope-session-cachyos` tried to launch missing optional binaries (`ibus-daemon`, `xbindkeys`, and `steam_notif_daemon`). They are packaging/session warnings and are outside this hardware-fix installer.
- Steam also called `/usr/lib/jupiter-dock-updater/jupiter-dock-updater.sh`, which is absent on this installation. Dock firmware updates through that helper are therefore unavailable until the distribution package supplies it.
- `/etc/vconsole.conf` requests `KEYMAP=ko`, which is not installed as a console keymap. Early boot logged two `loadkeys` failures before `systemd-vconsole-setup` completed successfully.
- PowerDevil logged repeated DDC/I²C `EREMOTEIO` failures on `/dev/i2c-12` during display redetection at 00:14. They did not coincide with a GPU reset or system restart; dock/display A/B testing is still needed to assess their impact.

## Tests still required before stronger claims

- Multiple long suspend/resume cycles, including battery drain measurement
- A 20–30 minute Space Marine 2 run at fixed 12 W, followed by a separate 15 W run if 12 W passes, because the old failure occurred after about five minutes
- Dock connect/disconnect testing with the internal panel active
- An ASPM-on/off comparison; the current run only establishes behavior with `pcie_aspm=off`
- An isolated comparison without `processor.max_cstate=1`, `idle=nomwait`, and `tsc=reliable`; these settings can trade idle power or clocksource fallback for fewer state transitions
- A full Steam download followed by SLC-folding cooldown measurement with the new APST setting
- Charge-bypass persistence and battery-current observation after reconnecting near 80%

Until those pass, the README describes the relevant settings as mitigations and measured behavior rather than complete fixes.
