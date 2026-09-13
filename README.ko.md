# AYANEO Slide & Antec Core HS 리눅스 최적화 패키지

[![Platform](https://img.shields.io/badge/Platform-CachyOS%20%7C%20Arch%20%7C%20Bazzite%20%7C%20SteamOS-1793D1?logo=arch-linux&logoColor=white)](https://cachyos.org)
[![Hardware](https://img.shields.io/badge/Hardware-AYANEO%20Slide%20%7C%20Antec%20Core%20HS-FF6600)]()
[![APU](https://img.shields.io/badge/APU-AMD%20Ryzen%207%207840U%20%2F%208840U-ED1C24?logo=amd&logoColor=white)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> [English (README.md)](README.md) | **[🇰🇷 한국어]**

**AYANEO Slide**(및 동일 기종인 **Antec Core HS**, AMD Ryzen 7 7840U / 8840U APU)를 리눅스(CachyOS, Bazzite, ChimeraOS, Arch Linux 등)에서 구동할 때 발생하는 **절전 모드 프리징, 영문 모를 강제 재부팅, SSD 절전 멈춤, 터치 좌표 오류** 등의 고질병들을 완벽하게 해결하는 원클릭 최적화 패키지입니다.

---

## 🎯 적용 대상 기기 및 환경

* **기기**: AYANEO Slide, Antec Core HS (AMD Ryzen 7 7840U / 8840U, Radeon 780M, 16GB / 24GB / 32GB LPDDR5X)
* **저장장치**: OEM 탑재 렉사 NM7A1 (DRAM-less, HMB) 포함 모든 NVMe SSD
* **지원 운영체제**: CachyOS (핸드헬드 에디션), Arch Linux, Bazzite, ChimeraOS, SteamOS (SteamFork)
* **부트로더**: Limine (CachyOS 기본), GRUB, systemd-boot

---

## 🛠 해결되는 고질적 하드웨어 결함 상세

| 문제 현상 | 발생 원인 | 해결책 (패키지 적용 내용) |
| :--- | :--- | :--- |
| **절전 모드(Sleep) 진입 후 영구 프리징**<br>*(전원 버튼으로 절전 진입 시 화면이 어두워진 채로 멈추며 버튼/화면 일체 반응 없음)* | 아야네오 슬라이드의 AMI 바이오스 ACPI DSDT 테이블에 비표준 전원 코드가 포함되어, 리눅스 커널 전원 관리자가 `s2idle` 진입 및 복귀 시 락업에 빠짐. | **`acpi=strict`**<br>커널이 제조사의 결함 있는 비표준 코드를 무시하고 엄격한 ACPI 국제 표준 규격만 따르도록 강제 (*ChimeraOS 이슈 #892 검증*). |
| **이유 없는 갑작스러운 재부팅 / 셧다운**<br>*(메뉴 화면이나 대기 상태에서 갑자기 화면이 꺼지며 재부팅, 하드웨어 에러 `0x08000800` 기록)* | AMD Zen 4 모바일 칩셋이 C3 초절전 상태로 들어갈 때 SoC 전압이 급락함. 코어 복귀 시 전압 강하(Voltage Droop)로 인해 AMD 인피니티 패브릭에 하드웨어 패리티 에러가 발생, CPU 다이가 강제 **Sync Flood** 리셋을 실행함. | **`processor.max_cstate=1`** & **`idle=nomwait`**<br>CPU 대기 상태를 안전한 C1으로 제한하여 전압 강하를 원천 차단. 불안정한 CachyOS BPF 스케줄러(`scx_loader`) 비활성화. |
| **렉사 NM790 NVMe SSD 절전 사망**<br>*(절전 모드 후 SSD가 PCIe 버스에서 분리되어 커널 패닉 및 I/O 멈춤 발생)* | MAP1602 DRAM-less 컨트롤러가 리눅스에서 딥슬립(APST PS4) 복귀 시 타임아웃을 일으켜 링크가 끊어짐. | **`nvme_core.default_ps_max_latency_us=0`**<br>NVMe SSD의 APST 대기 절전 모드를 비활성화하여 항상 안정적인 응답 대기 상태 유지. |
| **터치 입력이 엉뚱한 곳에 찍힘 (이중 회전)**<br>*(터치한 위치가 아닌 회전된 위치에 입력됨)* | 물리 패널이 1080x1920 세로(Portrait) 규격이라 KWin(Plasma Wayland)이 가로 출력 회전(output transform)을 터치 좌표에 자동 적용함. 여기에 udev `LIBINPUT_CALIBRATION_MATRIX` 90도 회전 매트릭스를 얹으면 좌표가 한 번 더 회전하여 반대편에 입력됨. | **캘리브레이션 매트릭스 미적용**<br>회전 보정은 컴포지터가 자체 처리하므로 이전 `99-ayaneo-slide-touchscreen.rules`는 제거됨. |
| **절전 중 조이스틱 RGB LED 배터리 방전**<br>*(기기가 절전 상태인데도 조이스틱 테두리 링 LED가 계속 깜빡이며 배터리를 소모함)* | 순정 펌웨어 기본값이 절전 중 점멸(`[oem] keep off`)로 되어 있음. | **`udev/99-ayaneo-slide-led-suspend.rules`**<br>절전 모드 진입 시 LED 전원을 완전히 끄는 `ATTR{suspend_mode}="off"` 규칙 적용. |
| **클럭소스 워치독 원격 CPU 타임아웃**<br>*(커널 로그에 `Watchdog remote CPU read timed out` 경고 발생)* | 전력 상태 전환 시 TSC 클럭 타이머 드리프트 발생. | **`tsc=reliable`**<br>16스레드 전체에서 invariant TSC를 신뢰할 수 있는 클럭소스로 고정. |
 | **도킹 허브 / 외장 모니터 연결 시 DCN 락업**<br>*(USB-C 도크 연결 시 커널에 `REG_WAIT timeout in dcn31_program_compbuf_size` 경고 발생)* | DCN 3.1.4 디스플레이 압축 버퍼가 대역폭 재할당 시 시스템 메모리 버스(Data Fabric)와 충돌하여 응답 타임아웃 발생. | **`amdgpu.sg_display=0`**<br>APU의 비연속적 Scatter-Gather 메모리 할당을 끄고 연속 VRAM을 강제하여 DCHUBBUB 동기화 락업 방지. |
| **eDP 패널 PSR 불안정**<br>*(Steam 실행, Proton prefix 세팅 등 GPU 부하 시 간헐적 데이터 패브릭 sync flood 재부팅 발생)* | DCN 3.1.4의 eDP PSR 전력 상태 전환이 Phoenix APU에서 디스플레이 파이프라인과 Data Fabric을 불안정하게 만듦. | **`amdgpu.dcdebugmask=0x10`**<br>PSR을 비활성화하여 eDP 링크를 활성 상태로 유지, GPU 클럭 전환 시 패브릭 오류 예방. |
| **3D / Proton 실행 시 Data Fabric Sync Flood [0x08000800]**<br>*(게임 실행이나 3D 그래픽 초기화 시 즉각적인 하드 셧다운/재부팅)* | 피닉스 APU의 통합 GPU가 그래픽 DMA 버퍼를 급격히 요청할 때 IOMMU 동적 주소 변환 페이지 테이블 워크 지연으로 데이터 패브릭 락업 발생. | **`iommu=pt`**<br>통합 장치에 대해 IOMMU를 Passthrough 모드로 설정하여 주소 변환 병목을 우회하고 메모리 컨트롤러 프리징 방지. |
| **NVMe 대용량 I/O 및 고부하 시 PCIe 전압 강하**<br>*(스팀 고속 다운로드나 셰이더 빌드 중 기기 멈춤 또는 재부팅)* | PCIe 능동 전원 관리(ASPM)가 고속 읽기/쓰기 중간중간 저전력 모드로 전환을 시도하면서 링크 지연 및 순간 전압 강하를 유발함. | **`pcie_aspm=off`**<br>PCIe ASPM 절전 상태를 꺼서 고부하 환경에서도 PCIe 링크를 풀 스피드로 상시 유지. |
| **디램리스 NVMe HMB 패브릭 충돌**<br>*(스팀 300Mbps 고속 다운로드 중 0x08000800 Sync Flood 재부팅, 드라이브 72°C 도달)* | 디램리스 컨트롤러가 시스템 램 32MB를 호스트 메모리 버퍼(HMB)로 쓰며 PCIe DMA를 지속하는데, 고부하·고온에서 DMA 동기화 불일치로 Data Fabric 락업 유발. | **디스크 쓰기 상한 + 온도 가드**<br>HMB는 **커널 6.9 이상에서 비활성화 불가** (`max_host_mem_size_mb` 파라미터가 업스트림에서 삭제되어 무시됨). 대신 설치 스크립트가 디스크 쓰기 대역폭을 상한 제한하고 발열 시 추가로 조임 (아래 NVMe 온도 가드 참조). 근본 해결은 DRAM 내장 SSD 교체. |
| **NVMe 온도 가드**<br>*(백스톱: 앱 속도 제한과 무관하게 지속 쓰기가 위험 온도에 못 가게 함)* | 이 기체 실측: 풀스피드 스팀 다운로드(약 40MB/s 지속 쓰기)는 써멀패드가 있어도 드라이브를 72°C까지 올리며, 이는 Sync Flood 크래시 온도와 일치. | **`ayaneo-nvme-guard.service` + cgroup `io.max`**<br>모든 사용자 애플리케이션에 적용되는 커널 레벨 25MB/s 쓰기 상한(앱 무관) + 69°C 이상 시 8MB/s로 조이고 66°C 이하에서 해제하는 온도 가드. 상태 확인: `journalctl -t ayaneo-nvme-guard -f`. |

---

## 🎛️ NVMe 보호 기능 튜닝

기본 구성은 **25MB/s 상시 쓰기 상한 + 온도 가드** (69°C 이상 시 8MB/s 조임, 66°C 이하 해제)입니다. 이 기체 실측: 40MB/s 지속 쓰기는 드라이브를 72°C(크래시존)까지 올리고, 25MB/s는 66~68°C에 머뭅니다.

**참고: 제한 값이 실제로 의미하는 것**

| 설정값 | 실제 속도 | 예상 NVMe 온도 | 평가 |
|---|---|---|---|
| 1500 KB/s | 1.5 MB/s | ~50°C | 매우 안전하지만 90GB 게임에 ~17시간 |
| 1500 Mbps | 187 MB/s | 72°C+ | 효과 없음 — WiFi가 어차피 ~40MB/s가 최대 |
| **15~25 MB/s** | — | **60~68°C** | 안전 구간; sync flood 온도 도달 불가 |

**방법 A — 정적 상한만 사용 (데몬 없음):** 동적 가드 대신 고정 값 하나를 선호하면:

```bash
sudo systemctl disable --now ayaneo-nvme-guard
sudo systemctl set-property user.slice IOWriteBandwidthMax="/dev/nvme0n1 20M"
```

**방법 B — HCTM (드라이브 자가 스로틀):** NVMe 기능 0x10은 호스트가 드라이브에게 지정 온도에서 *스스로* 속도를 줄이도록 지시하는 기능 — 펌웨어 레벨 디램리스 해결에 가장 가까운 수단. 지원 여부는 펌웨어에 따라 다름:

```bash
sudo pacman -S nvme-cli
sudo nvme get-feature /dev/nvme0 -f 0x10     # 지원 시 TMT1/TMT2 출력
# 60°C(333K)에서 자가 스로틀, 75°C(348K) 하드스톱으로 설정:
sudo nvme set-feature /dev/nvme0 -f 0x10 -v 0x015C014D
```

HCTM 온도는 켈빈(°C + 273)입니다. 설치 스크립트는 `nvme-cli`가 있으면 HCTM 지원 여부를 자동 탐지해 보고합니다.

**방법 C — 문제 클래스 자체 제거:** DRAM 내장 SSD로 교체 — HMB가 존재 자체를 멈춥니다.

---

## 🚀 빠른 설치 방법 (원클릭 한 줄 명령어)

데스크톱 모드의 터미널(Konsole)을 열고 아래 **한 줄 명령어**만 복사해서 붙여넣으시면 즉시 설치됩니다:

```bash
curl -sSL https://raw.githubusercontent.com/jshsakura/ayaneo-slide-linux-fixes/main/install.sh | sudo bash
```

설치가 완료되면 기기를 재부팅하여 커널에 변경 사항을 활성화합니다:

```bash
sudo systemctl reboot
```

<details>
<summary><b>대체 방법: Git 수동 클론 (Manual Git Clone)</b></summary>

```bash
git clone https://github.com/jshsakura/ayaneo-slide-linux-fixes.git
cd ayaneo-slide-linux-fixes
sudo bash install.sh
sudo systemctl reboot
```
</details>

### `install.sh` 스크립트 동작 과정
1. **안전 백업**: `/etc/default/limine`을 `/etc/default/limine.orig`로 자동 백업합니다.
2. **커널 파라미터 주입**: `acpi=strict`, `processor.max_cstate=1`, `idle=nomwait`, `nvme_core.default_ps_max_latency_us=0`, `tsc=reliable`, `amdgpu.sg_display=0`, `amdgpu.dcdebugmask=0x10`, `iommu=pt`, `pcie_aspm=off`를 부트로더에 안전하게 추가하고 무효 파라미터(`amdgpu.gfxoff=0`)를 정리합니다.
3. **스케줄러 안정화**: 실험적이고 불안정한 BPF CPU 스케줄러(`scx_loader`)를 영구 비활성화하고 정석 EEVDF 스케줄러로 복구합니다.
4. **하드웨어 udev 룰 등록**: 조이스틱 LED 절전 자동 소등 룰을 시스템에 등록합니다. (터치스크린 가로 보정은 컴포지터가 자체 처리하므로 룰을 별도로 설치하지 않습니다.)
5. **부트로더 갱신**: `limine-update`를 실행하여 새로운 커널 설정과 initramfs를 빌드합니다.

---

## ↩️ 원상 복구 (제거 방법)

모든 설정을 순정 상태로 되돌리고 싶으실 때는 아래 명령어를 실행하시면 됩니다:

```bash
cd ayaneo-slide-linux-fixes
sudo bash uninstall.sh
sudo systemctl reboot
```

---

## 🇰🇷 한국어 입력기(fcitx5) 설정 안내 (스팀덱 & 슬라이드 겸용)

아야네오 슬라이드의 물리 슬라이딩 키보드나 외장 키보드에서 **한/영 전환(오른쪽 Alt) 및 데스크톱 모드 한글 입력**이 필요하신 경우, 작성자의 스팀덱 & UMPC 전용 입력기 프로젝트인 **[`jshsakura/steamdeck`](https://github.com/jshsakura/steamdeck)**를 사용하여 아래 한 줄 명령어로 즉시 설정하실 수 있습니다:

```bash
curl -sSL https://raw.githubusercontent.com/jshsakura/steamdeck/main/install.sh | bash
```

* **게이밍 안전**: 게임 중 달리기+점프(`Shift + Space`) 시 입력기가 켜지는 충돌을 원천 차단 (`Shift+Space` 배제).
* **오른쪽 Alt 한영키 매핑**: 스페이스바 오른쪽 Alt를 누르면 윈도우처럼 즉시 한/영 전환 (`korean:ralt_rctrl`).
* **띄어쓰기 앞쏠림 버그 해결**: fcitx5의 단어 확정 버그(`WordCommit=False`) 자동 패치.
* **Wayland & 게이밍 환경 연동**: KDE Plasma Wayland 가상 키보드 및 Proton 게임 환경 변수 자동 주입.

---

## ⚙️ 권장 바이오스(BIOS) 설정

기기 성능과 안정성을 극대화하기 위해 다음 바이오스 설정을 권장합니다.  
*(부팅 시 볼륨(+) 버튼을 길게 누르거나 외장 키보드의 `Del` 키를 연타하여 진입)*

| 항목 | 권장값 | 기본값 | 이유 및 효과 |
| :--- | :---: | :---: | :--- |
| **UMA Frame buffer Size** | **`6G`** 또는 **`8G`** | Auto / 3G | 라데온 780M 내장 그래픽에 VRAM을 고정 할당합니다. 사이버펑크 2077, 엘든링 등 최신 게임 구동 시 비디오 메모리 부족으로 게임이 튕기는 OOM Crash를 완벽 차단합니다 (*슬라이드는 24GB 대용량 RAM 탑재*). |
| **fTPM** | **`Disabled`** | Enabled | AMD Zen 4 칩셋 특유의 간헐적 마이크로 스터터링(프레임 및 사운드가 0.5초간 뚝 끊기는 현상)을 방지합니다. 리눅스에서는 fTPM이 불필요합니다. |
| **Core Watchdog Timer** | **`Disabled`** | Enabled | 바이오스 하드웨어 감시자의 오작동으로 인한 갑작스러운 강제 재부팅을 방지합니다. |
| **IGD - AmdGop Output Priority** | **`LCD`** | CRT | 내부 디스플레이를 최우선 출력으로 지정하여 독(Dock) 연결이나 외부 디스플레이 분리 시 화면이 안 나오는 버그를 방지합니다. |

> 상세한 바이오스 설정 안내는 [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) 문서를 참고하세요.

---

## 🔋 추천 TDP 전력 프로필 (Decky Loader 활용)

스팀 게임모드에서 Decky Loader의 **SimpleDeckyTDP** 또는 **PowerTools** 플러그인을 사용하여 TDP를 제어하는 것을 권장합니다:

* **배터리 구동 시**: **`15W – 18W` 고정**
  * 7840U의 와트당 성능비(Sweet Spot)가 가장 높은 구간입니다. 20W 이상 부스트를 허용하면 발열이 심해지고 슬라이드의 46Wh 배터리 보호회로(BMS)에서 과전류 차단이 발생할 수 있습니다.
* **충전기 연결(시즈모드) 시**: **`22W – 28W`**
  * 슬라이드의 내장 쿨링팬으로 쾌적하게 고성능 게이밍이 가능합니다.
* **수동 GPU 클럭 고정**: **`1200MHz – 1600MHz`**
  * CPU와 GPU 간 전력 줄다리기를 막아 게임 내 1% Low 최저 프레임을 대폭 안정화합니다.

---

## 🔍 패치 정상 적용 여부 확인 방법

재부팅 후 터미널에서 다음 명령어들로 패치 활성화 여부를 즉시 검증할 수 있습니다:

```bash
# 1. 커널 부팅 파라미터 확인
cat /proc/cmdline
# 확인: acpi=strict, processor.max_cstate=1, idle=nomwait, nvme_core.default_ps_max_latency_us=0 포함 여부

# 2. C-state 전압 강하 차단 확인 (C2/C3가 사라지고 POLL과 C1만 존재해야 함)
ls /sys/devices/system/cpu/cpu0/cpuidle/
# 출력: state0 state1 (state2, state3이 없어야 정상)

# 3. 렉사 SSD 절전 파라미터 확인
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
# 출력: 0

# 4. 조이스틱 LED 절전 설정 확인
cat /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode
# 출력: [off] oem keep
```

---

## 📚 기술 문서 링크

* [docs/HARDWARE_ANALYSIS.md](docs/HARDWARE_ANALYSIS.md) — Data Fabric Sync Flood(`0x08000800`), ACPI DSDT 락업, 스팀 패드 숨김 구조에 대한 상세 기술 분석서
* [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) — 바이오스 최적화 단계별 가이드
* [README.md](README.md) — Global English Documentation

---

## 🤝 참고 문헌 및 커뮤니티 기여

* [ChimeraOS Issue #892](https://github.com/ChimeraOS/chimeraos/issues/892) — 아야네오 슬라이드 / Antec Core HS의 `acpi=strict` 해결책 발견
* [Valve Software SteamOS Issue #2757](https://github.com/ValveSoftware/SteamOS/issues/2757) — AMD Zen 4 인피니티 패브릭 Sync Flood 리셋 원인 규명
* [Bazzite Issue #5596 & #5508](https://github.com/ublue-os/bazzite/issues/5596) — 슬라이드 절전 루틴 및 입력 장치 분석
* [ShadowBlip / ayaneo-platform](https://github.com/ShadowBlip/ayaneo-platform) — 아야네오 리눅스 커널 플랫폼 드라이버

---

## 📜 라이선스

이 프로젝트는 [MIT License](LICENSE) 하에 자유롭게 수정 및 배포가 가능합니다. 버그 리포트와 풀 리퀘스트(PR)는 언제나 환영합니다!
