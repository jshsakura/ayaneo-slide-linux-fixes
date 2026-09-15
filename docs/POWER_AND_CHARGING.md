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

The live setting is `always`. Linux confirms that HHD maps this to:

```text
/sys/class/power_supply/BAT0/charge_behaviour
auto [inhibit-charge]
```

The brackets mark `inhibit-charge` as active. This is not a charge-limit option: it stops charging at the present battery level and has no percentage target. The other kernel label, `auto`, means normal charge behavior; it does not provide an HHD capacity-based policy. The OS can verify that charging is inhibited; it cannot independently measure the internal power rail to prove a hardware-level direct bypass.

At 100%, the binary bypass is still useful. The tested device currently reports `capacity=100`, `status=Full`, HHD `always`, and kernel `inhibit-charge`. Charging remains inhibited if capacity later reads 99%; select `disabled` when normal charging is wanted again. This can prevent repeated top-up cycles, but it does not reduce the cell voltage or provide the storage benefit of an actual 80% limit.

## Automatic bypass at 100%

The installer adds `ayaneo-charge-at-full.timer`. Every 30 seconds its oneshot helper reads `BAT0/capacity` and `BAT0/charge_behaviour`. It invokes HHD only when the selected kernel state needs to change:

| Reported capacity | Policy action | Result |
|---:|---|---|
| 100% or above | Select `always` | Charging inhibited |
| 96–99% | Keep the current state | Avoid 99↔100% top-up cycling |
| 95% or below | Select `disabled` | Normal charging allowed |

The matching-state path only reads sysfs and does not invoke HHD. This avoids continuous HHD calls and prevents the `always` mode from accidentally blocking recharge after the device has been used on battery. The uninstaller removes the timer and restores the bypass state recorded before installation.

Verify the automation with:

```bash
systemctl is-enabled ayaneo-charge-at-full.timer
systemctl status ayaneo-charge-at-full.timer --no-pager
journalctl -u ayaneo-charge-at-full.service --no-pager
```

The timer owns the bypass state while it is active. To hold the battery near 80% manually instead:

1. Stop the automatic policy with `sudo systemctl disable --now ayaneo-charge-at-full.timer`.
2. Unplug external power and use the device until the reported capacity reaches about 80%.
3. Select Charge Bypass `always`, then reconnect power. Bypass remains active and inhibits charging at that level.

Re-enable the automatic 100% policy with `sudo systemctl enable --now ayaneo-charge-at-full.timer`.

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

This automatic policy implements a fixed 95–100% window around the reported battery capacity. It is not a firmware-backed programmable 80% threshold, and it does not need the missing separate AC-supply status node.

References:

- [AMD Ryzen 7 7840U specifications](https://www.amd.com/en/products/processors/laptop/ryzen/7000-series/amd-ryzen-7-7840u.html)
- [Linux power-supply class](https://cdn.kernel.org/doc/html/latest/power/power_supply_class.html)
