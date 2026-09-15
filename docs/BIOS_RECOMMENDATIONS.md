# AYANEO Slide & Antec Core HS - BIOS Optimization Guide

This guide details the recommended BIOS settings for the **AYANEO Slide** (and **Antec Core HS**, AMD Ryzen 7 7840U / 8840U) running Linux (CachyOS, Bazzite, ChimeraOS, SteamOS).

---

## 🔑 Entering the BIOS
1. Turn on the device from a complete power-off state.
2. Immediately press `Del` repeatedly on a connected keyboard, or repeatedly press the **Volume (+)** button.

---

## 🛠 Recommended Settings

| Setting | Recommended Value | Default | Rationale |
| :--- | :---: | :---: | :--- |
| **UMA Frame buffer Size** | **`6G` tested** | Auto / 3G | Reserves enough Radeon 780M memory for the tested games while leaving 18 GiB of the device's 24 GiB for Linux. This reduces VRAM exhaustion; it does not guarantee that every game cannot OOM. |
| **fTPM** | **Keep default** | Enabled | No fTPM fault appears in the collected logs. Leave it enabled unless an fTPM-specific stall is reproduced and disk-encryption implications are understood. |
| **Core Watchdog Timer** | **Keep default** | Enabled | The observed CF9 software-reset record does not establish a false watchdog trigger. Leave it enabled unless an isolated test proves otherwise. |
| **IGD - AmdGop Output Priority** | **`LCD`** | CRT | Prioritizes the internal display during early boot, preventing black-screen issues on docks or external monitors. |

---

## ⚡ Battery & TDP Best Practices (via Decky Loader)

* Use **8–10 W** for light games and maximum battery life.
* Use **12 W, TDP boost off, GPU auto** as the current Slide stability baseline.
* Treat **15 W** as the general 7840U efficiency/performance target only after the same demanding game passes for 20–30 minutes at 12 W.
* TDP boost raises bounded Fast/Slow limits; it is not unlimited. Leave it off for GPU-limited games and test it only for CPU-heavy games or emulators.
* Start demanding games at a 30 FPS cap; raise the cap to 40 FPS only when frame delivery remains stable.
* Treat AC and battery as separate tests. A charger does not by itself validate 22–28 W operation.
* The installer intentionally leaves the user's HHD TDP unchanged.

## 🔌 Charge Limit Is Unsupported; Bypass Only

The tested Slide has no charge-limit option or firmware-backed 80% threshold. A separate Charge Bypass switch has only `disabled` and `always`; with `always` selected, Linux reports `inhibit-charge`. Discharge to the desired level before reconnecting external power. See [POWER_AND_CHARGING.md](POWER_AND_CHARGING.md) for commands and limitations.
