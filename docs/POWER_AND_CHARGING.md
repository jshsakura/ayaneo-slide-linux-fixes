# TDP, Boost, and Charge Bypass

These settings were inspected on the author's physical AYANEO Slide with HHD 4.1.12. HHD names and available choices can change in later releases.

## Recommended power profiles

| Workload | Sustained TDP | TDP boost | GPU frequency | Purpose |
|---|---:|---|---|---|
| Light games and maximum battery life | 8–10 W | Off | Auto | Lowest practical power profile |
| Current Slide stability baseline | 12 W | Off | Auto | First profile to use for demanding games on this device |
| General 7840U efficiency/performance target | 15 W | Off | Auto | Use only after the same game passes the 12 W stability test |
| CPU-limited game or emulator | 12–15 W | Test on/off | Auto | Enable boost only when measured frame time or emulation speed improves |

AMD specifies a 15–30 W configurable-TDP range for the Ryzen 7 7840U. That makes 15 W a reasonable general efficiency target, but it is not proof that every handheld power path is stable there. This Slide previously powered off during Space Marine 2, so 12 W with boost disabled remains the device-specific starting point until a 20–30 minute repeat passes.

For demanding games, begin with a 30 FPS cap. Use 40 FPS only when the workload sustains it without repeated frame-time misses; this avoids spending power on frames that do not produce a stable presentation cadence.

## What HHD's TDP boost changes

TDP boost is bounded; it does not allow unlimited power. HHD raises the short-duration Fast and Slow limits while the sustained Skin/STAPM limit remains at the selected TDP.

On this device, an 8 W profile with boost enabled reported 10 W Fast/Slow limits and an 8 W sustained limit. Disabling boost made Fast, Slow, Skin, and STAPM all equal to 8 W. At the current 12 W profile with boost disabled, all four limits report 12 W.

The CPU and Radeon 780M share the same package power budget. In a GPU-limited game, a CPU boost transient can consume power and thermal headroom that the GPU could otherwise use. This can add heat or frame-time variation without improving average frame rate. CPU-heavy emulators are the main case where enabling boost may help, and that should be decided with an A/B measurement.

The installer preserves the user's sustained TDP and disables QAM TDP boost. It leaves GPU frequency management on automatic.

To apply and verify the 12 W baseline manually:

```bash
HHDCTL="$HOME/.local/share/hhd/venv/bin/hhdctl"
sudo "$HHDCTL" set tdp.qam.tdp=12 tdp.qam.boost=false
"$HHDCTL" get tdp.qam.tdp tdp.qam.boost
```

After the demanding-game test passes, replace `12` with `15` to test the general efficiency target. Keep boost off for that first comparison.

## No percentage charge limit; binary bypass only

The Slide does **not** expose a charge-limit control. HHD's hardware probe printed a valid path after `Battery Bypass` and no path after `Battery Limit`. Linux likewise exposes no `charge_control_start_threshold` or `charge_control_end_threshold`. There is no hidden 80% slider or selectable percentage.

A separate, binary charge-inhibit backend exists. Its HHD states are:

```text
tdp.battery.charge_bypass: disabled | always
```

HHD maps its two settings to the kernel interface as follows:

```text
disabled -> [auto] inhibit-charge
always   -> auto [inhibit-charge]
```

The brackets mark the active value. The local `ayaneo_platform` source confirms that `auto` writes `0x65` to EC register `0xd1` to close direct bypass, while `inhibit-charge` writes `0x01` to open it. The driver reacts only to a requested state change and contains no capacity-reading or percentage-trigger logic.

Normal `[auto]` mode still performs ordinary full-charge termination through the EC and battery-management system. On the tested device, HHD `disabled` and kernel `[auto]` remained at `capacity=100`, `status=Full`, and `energy_now=energy_full` for seven samples over 35 seconds; `power_now` stayed at approximately 0.161 W. This verifies that a polling service is unnecessary merely to stop charging at 100%. It does not prove whether the internal power rail in normal full-charge mode is identical to forced direct bypass.

Forced bypass remains available manually. With `always`, charging stays inhibited even after the capacity falls below 100%; select `disabled` to resume normal charging. Forced bypass does not lower the battery from its current state of charge.

To hold the battery near 80%:

1. Leave Charge Bypass on `always` and unplug external power.
2. Use the battery until it reaches about 80%.
3. Reconnect external power while Charge Bypass remains on `always`.
4. Recheck the capacity and charge behavior after reconnecting or rebooting.

The backend can be inspected or changed with commands even when no percentage-limit control exists:

```bash
HHDCTL="$HOME/.local/share/hhd/venv/bin/hhdctl"

# Inspect the HHD and kernel states
"$HHDCTL" get tdp.battery.charge_bypass --values --sep=''
cat /sys/class/power_supply/BAT0/charge_behaviour

# Inhibit charging at the present battery level
sudo "$HHDCTL" set tdp.battery.charge_bypass=always

# Resume normal charging
sudo "$HHDCTL" set tdp.battery.charge_bypass=disabled
```

Do not install a polling service merely to reproduce the full-charge cutoff already provided by the EC/BMS. This system exposes only `BAT0`, has no separate AC-supply status node, and cannot command the battery to discharge to a target while external power remains connected.

References:

- [AMD Ryzen 7 7840U specifications](https://www.amd.com/en/products/processors/laptop/ryzen/7000-series/amd-ryzen-7-7840u.html)
- [Linux power-supply class](https://cdn.kernel.org/doc/html/latest/power/power_supply_class.html)
