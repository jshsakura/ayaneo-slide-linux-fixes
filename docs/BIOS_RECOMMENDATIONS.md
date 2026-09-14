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

* Begin at **8–12 W**, disable CPU boost, and leave GPU frequency on `auto`.
* Repeat a previously failing game for at least 20–30 minutes before raising TDP.
* Treat AC and battery as separate tests. A charger does not by itself validate 22–28 W operation.
* The installer intentionally leaves the user's HHD TDP unchanged.
