# AYANEO Slide (and Antec Core HS) Linux / CachyOS Community Fixes Suite

[![Platform](https://img.shields.io/badge/platform-CachyOS%20%7C%20Arch%20%7C%20Bazzite%20%7C%20ChimeraOS-blue.svg)](https://cachyos.org)
[![Hardware](https://img.shields.io/badge/device-AYANEO%20Slide%20%7C%20Antec%20Core%20HS-orange.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

[**한국어 설명서**](#한국어-안내) | [**English Guide**](#english-guide)

---

## 한국어 안내

**AYANEO Slide** (및 리브랜딩 기종인 **Antec Core HS**, AMD Ryzen 7 7840U / 8840U)를 리눅스(CachyOS, Bazzite, ChimeraOS, Arch Linux)에서 구동할 때 발생하는 모든 고질적인 하드웨어 결함과 절전/전원 문제를 원클릭으로 해결하는 최적화 패키지입니다.

### 🛠 해결되는 문제 목록
1. **절전 모드(Sleep) 진입 후 화면 멈춤 및 먹통 현상 완전 해결**:
   * 슬라이드 특유의 AMI 바이오스 ACPI DSDT 버그를 **`acpi=strict`** 커널 파라미터로 무력화하여 절전 진입/복귀 프리징을 완벽하게 차단합니다.
2. **이유 없는 갑작스러운 재부팅 및 셧다운(Data Fabric Sync Flood `0x08000800`) 방지**:
   * 배터리 구동 시 유휴 상태에서 발생하는 전압 강하(Voltage Droop)를 **`processor.max_cstate=1`** 및 **`idle=nomwait`**로 방지하고 불안정한 BPF 스케줄러(`scx_loader`)를 비활성화합니다.
3. **렉사 NM790 NVMe SSD 절전 사망 버그 해결**:
   * MAP1602 DRAM-less 컨트롤러가 APST 절전 후 깨어나지 못해 커널이 정지하는 문제를 **`nvme_core.default_ps_max_latency_us=0`**으로 해결합니다.
4. **터치스크린 가로(Landscape) 좌표 자동 보정**:
   * 세로 패널로 인해 90도 회전되어 터치되던 문제를 udev 보정 매트릭스로 즉시 교정합니다.
5. **절전 중 조이스틱 RGB LED 배터리 소모 방지**:
   * 절전 모드 진입 시 조이스틱 테두리 RGB LED가 자동으로 완전히 소등(`suspend_mode=off`)되도록 udev 규칙을 적용합니다.

---

### 🚀 설치 방법

터미널을 열고 아래 명령어를 입력하여 설치를 진행합니다:

```bash
git clone https://github.com/<your-username>/ayaneo-slide-linux-fixes.git
cd ayaneo-slide-linux-fixes
sudo bash install.sh
```

설치 완료 후 기기를 재부팅하시면 모든 패치가 활성화됩니다:
```bash
sudo systemctl reboot
```

---

### 📖 권장 바이오스(BIOS) 설정
더 나은 안정성과 성능을 위해 다음 설정을 권장합니다:
* **UMA Frame buffer Size**: `6G` 또는 `8G` (VRAM 부족으로 인한 게임 튕김 방지)
* **fTPM**: `Disabled` (간헐적 마이크로 스터터링 방지)
* **Core Watchdog Timer**: `Disabled` (오작동 하드웨어 리셋 방지)
* **IGD - AmdGop Output Priority**: `LCD` (내부 디스플레이 우선)

자세한 내용은 [BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) 문서를 참고하세요.

---

## English Guide

A comprehensive, community-tested optimization suite for the **AYANEO Slide** and **Antec Core HS** handhelds running Linux (CachyOS, Bazzite, ChimeraOS, Arch Linux).

### 🛠 Resolved Hardware Issues
* **Sleep/Wake Freeze Fix**: Resolves the notorious AMI BIOS ACPI sleep lockup using `acpi=strict`.
* **Spontaneous Hard Resets Fix**: Eliminates AMD Zen 4 Data Fabric Sync Flood hardware resets (`0x08000800`) using `processor.max_cstate=1` and `idle=nomwait`.
* **Lexar NM790 / MAP1602 SSD Wake Freeze**: Prevents PCIe bus dropouts with `nvme_core.default_ps_max_latency_us=0`.
* **Touchscreen Calibration**: Injects 90° landscape transformation matrix.
* **RGB LED Sleep Auto-Off**: Automatically powers down joystick ring LEDs during suspend.

### 🚀 Quick Installation

```bash
git clone https://github.com/<your-username>/ayaneo-slide-linux-fixes.git
cd ayaneo-slide-linux-fixes
sudo bash install.sh
sudo systemctl reboot
```

---

## 📜 License
Released under the [MIT License](LICENSE).
