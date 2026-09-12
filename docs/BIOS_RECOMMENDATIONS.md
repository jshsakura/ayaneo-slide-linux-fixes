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
| **UMA Frame buffer Size** | **`6G`** or **`8G`** | Auto / 3G | Allocates dedicated VRAM to the Radeon 780M iGPU. Eliminates out-of-memory game crashes (OOM) in modern AAA games (e.g., Cyberpunk 2077, Elden Ring). |
| **fTPM** | **`Disabled`** | Enabled | Prevents intermittent micro-stuttering and audio dropouts known across AMD Zen 4 mobile APUs on Linux. |
| **Core Watchdog Timer** | **`Disabled`** | Enabled | Prevents unexpected hardware resets caused by false-positive watchdog stalls. |
| **IGD - AmdGop Output Priority** | **`LCD`** | CRT | Prioritizes the internal display during early boot, preventing black-screen issues on docks or external monitors. |

---

## ⚡ Battery & TDP Best Practices (via Decky Loader)

* **On Battery**: Set TDP to **`15W – 18W`**.
  * The 7840U operates at peak efficiency (perf-per-watt sweet spot) in this range.
  * Prevents BMS voltage drop cutoffs caused by >25W transient spikes on the Slide's 46Wh battery.
* **On AC Power (Docked)**: Set TDP to **`22W – 28W`**.
* **Manual GPU Clock**: Lock GPU clock between **`1200MHz – 1600MHz`** to improve 1% low frame rate consistency.
