# AYANEO Slide & Antec Core HS 리눅스 최적화 패키지

[![Platform](https://img.shields.io/badge/Platform-CachyOS%20%7C%20Arch%20%7C%20Bazzite%20%7C%20SteamOS-1793D1?logo=arch-linux&logoColor=white)](https://cachyos.org)
[![Hardware](https://img.shields.io/badge/Hardware-AYANEO%20Slide%20%7C%20Antec%20Core%20HS-FF6600)]()
[![APU](https://img.shields.io/badge/APU-AMD%20Ryzen%207%207840U%20%2F%208840U-ED1C24?logo=amd&logoColor=white)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> [English (README.md)](README.md) | **[🇰🇷 한국어]**

**AYANEO Slide**(및 동일 기종인 **Antec Core HS**, AMD Ryzen 7 7840U / 8840U APU)의 리눅스 전원 관리, 컨트롤러 충돌, NVMe 대기 발열 문제를 이 기체에서 확인한 값에 맞춰 조정하는 설치 패키지입니다.

## 이 프로젝트를 만든 이유

아야네오 슬라이드에서 새로운 리눅스 배포판을 시험할 때마다 같은 커널 옵션과 서비스 충돌 해결법을 다시 찾아 헤매야 했습니다. 배포판만 바뀌었을 뿐인데 절전, 컨트롤러, TDP, 화면, NVMe 설정을 처음부터 다시 조사하는 일이 반복되는 게 너무 답답해서 이 프로젝트를 만들었습니다.

인터넷에서 찾은 옵션을 그대로 모아둔 목록이 아닙니다. 제가 사용하는 **실제 AYANEO Slide**에 직접 적용하고 부팅 로그, 서비스 상태, 게임 실행, 다운로드 부하, SSD 전력 상태와 온도를 비교한 결과를 설치와 원상 복구가 가능한 형태로 정리했습니다. 확인되지 않은 원인은 단정하지 않고, 실기에서 새 증거가 나오면 설정과 문서도 함께 고칩니다.

> **NVMe 수정 배경:** 원래 `nvme_core.default_ps_max_latency_us=0`은 렉사 NM7A1이 절전 후 깨어나지 못하는 문제를 피하려고 APST를 통째로 끈 응급조치였습니다. 이 값은 문제가 되는 PS4와 함께 안전한 PS3도 막아, 아무 작업이 없어도 컨트롤러가 운용 상태에 남고 68–72°C를 유지하는 부작용을 만들었습니다. 현재 설정 `15000`은 **PS4 차단을 유지하면서 50mW PS3만 복구**합니다.

---

## 🎯 적용 대상 기기 및 환경

* **기기**: AYANEO Slide, Antec Core HS (AMD Ryzen 7 7840U / 8840U, Radeon 780M, 16GB / 24GB / 32GB LPDDR5X)
* **저장장치**: OEM 렉사 NM7A1 2TB(펌웨어 9742, Maxio MAP1602, DRAM-less/HMB)에서 검증. 다른 NVMe는 같은 15ms 지연 한도 안에서 각자의 전력 상태를 선택함
* **지원 운영체제**: CachyOS (핸드헬드 에디션), Arch Linux, Bazzite, ChimeraOS, SteamOS (SteamFork)
* **부트로더**: Limine (CachyOS 기본), GRUB, systemd-boot

---

## 🛠 해결되는 고질적 하드웨어 결함 상세

| 문제 현상 | 발생 원인 | 해결책 (패키지 적용 내용) |
| :--- | :--- | :--- |
| **절전 모드(Sleep) 진입 후 영구 프리징**<br>*(전원 버튼으로 절전 진입 시 화면이 어두워진 채로 멈추며 버튼/화면 일체 반응 없음)* | 아야네오 슬라이드의 AMI 바이오스 ACPI DSDT 테이블에 비표준 전원 코드가 포함되어, 리눅스 커널 전원 관리자가 `s2idle` 진입 및 복귀 시 락업에 빠짐. | **`acpi=strict`**<br>커널이 제조사의 결함 있는 비표준 코드를 무시하고 엄격한 ACPI 국제 표준 규격만 따르도록 강제 (*ChimeraOS 이슈 #892 검증*). |
| **갑작스러운 재부팅 / 셧다운** | 실제 고장 세션은 정상 종료·OOM·NVMe 오류 없이 로그가 끊겼음. 다음 부팅의 `0x00080800`은 CF9 소프트웨어 리셋 기록이라 원인을 단독으로 증명하지 못함. 당시 HHD가 없고 UMA는 512MiB였음. | **HHD 12W, boost off + `processor.max_cstate=1` + `idle=nomwait`**<br>전력 관리자를 하나만 유지하고 깊은 CPU idle 전환을 피함. UMA는 이 기체에서 6GiB로 설정해 게임 VRAM 부족도 분리함. |
| **렉사 NM790 절전 복귀 실패와 높은 대기 온도** | 절전 복귀 실패를 피하려고 넣은 `default_ps_max_latency_us=0`이 APST를 통째로 꺼 컨트롤러를 계속 활성 상태로 둠. NM7A1의 PS3는 진입 5ms + 복귀 10ms, PS4는 진입 8ms + 복귀 45ms로 보고됨. | **`nvme_core.default_ps_max_latency_us=15000`**<br>원래 대응 목적대로 딥슬립 PS4는 계속 배제하면서 50mW PS3만 허용. I/O 속도 제한 없이 대기 부하를 낮춤. PCIe 링크 ASPM은 기체 안정성을 위해 계속 비활성화. |
| **터치 입력이 엉뚱한 곳에 찍힘 (이중 회전)**<br>*(터치한 위치가 아닌 회전된 위치에 입력됨)* | 물리 패널이 1080x1920 세로(Portrait) 규격이라 KWin(Plasma Wayland)이 가로 출력 회전(output transform)을 터치 좌표에 자동 적용함. 여기에 udev `LIBINPUT_CALIBRATION_MATRIX` 90도 회전 매트릭스를 얹으면 좌표가 한 번 더 회전하여 반대편에 입력됨. | **캘리브레이션 매트릭스 미적용**<br>회전 보정은 컴포지터가 자체 처리하므로 이전 `99-ayaneo-slide-touchscreen.rules`는 제거됨. |
| **절전 중 조이스틱 RGB LED 배터리 방전**<br>*(기기가 절전 상태인데도 조이스틱 테두리 링 LED가 계속 깜빡이며 배터리를 소모함)* | 순정 펌웨어 기본값이 절전 중 점멸(`[oem] keep off`)로 되어 있음. | **`udev/99-ayaneo-slide-led-suspend.rules`**<br>절전 모드 진입 시 LED 전원을 완전히 끄는 `ATTR{suspend_mode}="off"` 규칙 적용. |
| **클럭소스 워치독 원격 CPU 타임아웃**<br>*(커널 로그에 `Watchdog remote CPU read timed out` 경고 발생)* | 전력 상태 전환 시 TSC 클럭 타이머 드리프트 발생. | **`tsc=reliable`**<br>16스레드 전체에서 invariant TSC를 신뢰할 수 있는 클럭소스로 고정. |
 | **도킹 허브 / 외장 모니터 연결 시 DCN 락업**<br>*(USB-C 도크 연결 시 커널에 `REG_WAIT timeout in dcn31_program_compbuf_size` 경고 발생)* | DCN 3.1.4 디스플레이 압축 버퍼가 대역폭 재할당 시 시스템 메모리 버스(Data Fabric)와 충돌하여 응답 타임아웃 발생. | **`amdgpu.sg_display=0`**<br>APU의 비연속적 Scatter-Gather 메모리 할당을 끄고 연속 VRAM을 강제하여 DCHUBBUB 동기화 락업 방지. |
| **eDP 패널 PSR 불안정**<br>*(화면 전환 시 점멸·검은 화면)* | DCN 3.1.4의 eDP PSR 전력 상태 전환이 GPU 클럭 변경과 겹칠 수 있음. | **`amdgpu.dcdebugmask=0x10`**<br>PSR을 비활성화해 내부 패널 링크 상태 변화를 줄임. |
| **3D / Proton 실행 안정성** | 통합 GPU와 NVMe가 시스템 메모리 대역폭을 공유하므로 3D 초기화 때 IOMMU 변환 부하가 커질 수 있음. 이 기체의 과거 강제 재부팅 원인을 특정 오류 하나로 단정할 로그는 없음. | **`iommu=pt`**<br>통합 장치의 IOMMU 변환 오버헤드를 줄이는 보수적 설정. |
| **NVMe 대용량 I/O 및 고부하 시 PCIe 전압 강하**<br>*(스팀 고속 다운로드나 셰이더 빌드 중 기기 멈춤 또는 재부팅)* | PCIe 능동 전원 관리(ASPM)가 고속 읽기/쓰기 중간중간 저전력 모드로 전환을 시도하면서 링크 지연 및 순간 전압 강하를 유발함. | **`pcie_aspm=off`**<br>PCIe ASPM 절전 상태를 꺼서 고부하 환경에서도 PCIe 링크를 풀 스피드로 상시 유지. |
| **디램리스 NVMe의 HMB 사용** | NM7A1은 자체 DRAM 대신 시스템 램을 HMB로 사용함. 이 장치는 희망값과 최소값을 모두 8192페이지로 보고하며 커널은 요청량 전부를 할당함. | **32MiB HMB 유지**<br>실측에서 HMB는 32MiB로 정상 활성화됨. RAM을 더 할당하는 설정은 컨트롤러가 요청하거나 지원하지 않으며, HMB를 끄면 주소 변환 효율만 악화됨. |

---

## 🎛️ NVMe 전력 관리 방식

설치기는 `nvme_core.default_ps_max_latency_us=15000`을 적용합니다. NM7A1이 보고한 전력 상태를 기준으로 15ms 한도는 50mW PS3를 정확히 포함하고, 총 전환 지연이 53ms인 PS4는 제외합니다. 100ms 동안 I/O가 없으면 PS3로 들어가고, I/O가 시작되면 운용 상태로 복귀하므로 다운로드와 게임 읽기 속도에는 상한이 생기지 않습니다. `pcie_aspm=off`는 기체의 링크 안정성을 위해 유지하되 SSD 컨트롤러 내부 APST만 허용합니다.

이전 버전의 `ayaneo-nvme-guard.service`와 `app.slice` 쓰기 제한은 설치 과정에서 자동 제거됩니다. APST와 현재 HMB 상태는 다음처럼 확인할 수 있습니다.

```bash
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
sudo nvme get-feature /dev/nvme0 -f 0x0c -H
sudo nvme get-feature /dev/nvme0 -f 0x0d -H
```

정상값은 각각 `15000`, `APSTE: Enabled`, `HSIZE: 8192`(32MiB)입니다.

### 이 기체 실측 (2026-09-15)

| 항목 | APST 완전 비활성 | 15ms 한도 적용 후 |
|---|---:|---:|
| 컨트롤러/Composite | 68–72°C | 재부팅 후 64–65°C |
| NAND Sensor 2 | 50–55°C | 52°C |
| 앱 쓰기 제한 | 25MB/s | 없음 |
| 커널 NVMe/AER 오류 | 없음 | 없음 |

온도는 주변 온도와 직전 쓰기 작업에 따라 달라집니다. 다운로드 직후에는 호스트 쓰기가 끝나도 SLC 캐시 정리와 가비지 컬렉션 때문에 컨트롤러 온도가 잠시 높게 유지될 수 있습니다.

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
2. **커널 파라미터 주입**: `acpi=strict`, `processor.max_cstate=1`, `idle=nomwait`, `nvme_core.default_ps_max_latency_us=15000`, `tsc=reliable`, `amdgpu.sg_display=0`, `amdgpu.dcdebugmask=0x10`, `iommu=pt`, `pcie_aspm=off`를 부트로더에 안전하게 추가하고 무효 파라미터(`amdgpu.gfxoff=0`)를 정리합니다.
3. **스케줄러 안정화**: 실험적이고 불안정한 BPF CPU 스케줄러(`scx_loader`)를 영구 비활성화하고 정석 EEVDF 스케줄러로 복구합니다.
4. **하드웨어 udev 룰 등록**: 조이스틱 LED 절전 자동 소등 룰을 시스템에 등록합니다. (터치스크린 가로 보정은 컴포지터가 자체 처리하므로 룰을 별도로 설치하지 않습니다.)
5. **부트로더 갱신**: `limine-update`를 실행하여 새로운 커널 설정과 initramfs를 빌드합니다.
6. **NVMe 전력 관리**: 실행 중인 컨트롤러의 PM QoS도 15ms로 즉시 갱신하고, 구버전의 `ayaneo-nvme-guard`와 `app.slice` 쓰기 제한을 제거합니다.

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
| **UMA Frame buffer Size** | **`6G`** 또는 **`8G`** | Auto / 3G | 라데온 780M 내장 그래픽에 VRAM을 고정 할당해 게임의 비디오 메모리 부족 가능성을 낮춥니다 (*슬라이드는 24GB RAM 탑재*). |
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
# 확인: acpi=strict, processor.max_cstate=1, idle=nomwait, nvme_core.default_ps_max_latency_us=15000 포함 여부

# 2. C-state 전압 강하 차단 확인 (C2/C3가 사라지고 POLL과 C1만 존재해야 함)
ls /sys/devices/system/cpu/cpu0/cpuidle/
# 출력: state0 state1 (state2, state3이 없어야 정상)

# 3. 렉사 SSD 절전 파라미터 확인
cat /sys/module/nvme_core/parameters/default_ps_max_latency_us
# 출력: 15000

# APST가 켜졌고 NM7A1의 전이 대상이 PS3인지 확인
sudo nvme get-feature /dev/nvme0 -f 0x0c -H
# 출력: APSTE: Enabled, ITPS: 3

# 구버전 쓰기 제한이 제거됐는지 확인 (빈 출력이 정상)
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/io.max

# 4. 조이스틱 LED 절전 설정 확인
cat /sys/class/leds/ayaneo:rgb:joystick_rings/suspend_mode
# 출력: [off] oem keep
```

---

## 📚 기술 문서 링크

* [docs/HARDWARE_ANALYSIS.md](docs/HARDWARE_ANALYSIS.md) — 실측 NVMe 전력 상태, HMB, 온도, 재부팅 로그와 컨트롤러 스택 분석
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
