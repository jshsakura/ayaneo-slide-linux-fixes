# AYANEO Slide & Antec Core HS 리눅스 최적화 패키지

[![Platform](https://img.shields.io/badge/Platform-CachyOS%20%7C%20Arch-1793D1?logo=arch-linux&logoColor=white)](https://cachyos.org)
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
* **자동 설치 지원**: CachyOS Deckify / Arch 계열 + `pacman` + Limine
* **참고용**: Bazzite, ChimeraOS, SteamOS, GRUB, systemd-boot에서는 설정 원리를 참고할 수 있지만 설치기가 부팅 옵션을 자동 적용하지 않음

---

## 🛠 문제별 설정과 확인 근거

| 문제 현상 | 관찰 및 판단 | 적용 설정 |
| :--- | :--- | :--- |
| **절전 모드 진입 후 복귀 실패** | 이 문제 때문에 처음에는 NVMe APST를 통째로 껐음. ACPI와 NM7A1 PS4 복귀 경로가 모두 후보이며 현재 로그만으로 하나를 단정하지 않음. 새 설정에서 15초 `s2idle` 1회는 정상 복귀함. | **`acpi=strict` + NVMe APST 15ms 한도**<br>커뮤니티에서 사용된 ACPI 완화책을 유지하고 NM7A1 PS4를 제외함. 장시간·반복 슬립 검증은 아직 남아 있음. |
| **갑작스러운 재부팅 / 셧다운** | 실제 고장 세션은 정상 종료·OOM·NVMe 오류 없이 로그가 끊겼음. 다음 부팅의 `0x00080800`은 CF9 소프트웨어 리셋 기록이라 원인을 단독으로 증명하지 못함. 당시 HHD가 없고 UMA는 512MiB였음. | **HHD 단독 사용 + 이 기체의 12W 기준 + boost off + `processor.max_cstate=1` + `idle=nomwait`**<br>전력 관리자를 하나만 유지하고 깊은 CPU idle 전환을 피함. 설치기는 사용자가 선택한 지속 TDP는 보존하고 QAM boost만 끔. UMA는 이 기체에서 6GiB로 설정해 게임 VRAM 부족도 분리함. |
| **렉사 NM790 절전 복귀 실패와 높은 대기 온도** | 절전 복귀 실패를 피하려고 넣은 `default_ps_max_latency_us=0`이 APST를 통째로 꺼 컨트롤러를 계속 활성 상태로 둠. NM7A1의 PS3는 진입 5ms + 복귀 10ms, PS4는 진입 8ms + 복귀 45ms로 보고됨. | **`nvme_core.default_ps_max_latency_us=15000`**<br>원래 대응 목적대로 딥슬립 PS4는 계속 배제하면서 50mW PS3만 허용. I/O 속도 제한 없이 대기 부하를 낮춤. PCIe 링크 ASPM은 기체 안정성을 위해 계속 비활성화. |
| **터치 입력이 엉뚱한 곳에 찍힘 (이중 회전)**<br>*(터치한 위치가 아닌 회전된 위치에 입력됨)* | 물리 패널이 1080x1920 세로(Portrait) 규격이라 KWin(Plasma Wayland)이 가로 출력 회전(output transform)을 터치 좌표에 자동 적용함. 여기에 udev `LIBINPUT_CALIBRATION_MATRIX` 90도 회전 매트릭스를 얹으면 좌표가 한 번 더 회전하여 반대편에 입력됨. | **캘리브레이션 매트릭스 미적용**<br>회전 보정은 컴포지터가 자체 처리하므로 이전 `99-ayaneo-slide-touchscreen.rules`는 제거됨. |
| **절전 중 조이스틱 RGB LED 배터리 방전**<br>*(기기가 절전 상태인데도 조이스틱 테두리 링 LED가 계속 깜빡이며 배터리를 소모함)* | 순정 펌웨어 기본값이 절전 중 점멸(`[oem] keep off`)로 되어 있음. | **`udev/99-ayaneo-slide-led-suspend.rules`**<br>절전 모드 진입 시 LED 전원을 완전히 끄는 `ATTR{suspend_mode}="off"` 규칙 적용. |
| **클럭소스 워치독 경고**<br>*(과거 로그의 `Watchdog remote CPU read timed out`)* | 현재 부팅은 TSC를 사용하며 클럭소스 경고가 없지만, 과거 경고가 주파수 변화 때문이라는 A/B 근거는 없음. | **기준 설정으로 `tsc=reliable` 유지**<br>커널에 TSC를 신뢰하라고 지시해 워치독 기반 대체 전환을 억제할 수 있으므로 원인 해결이 아닌 완화책임. |
| **DCN 디스플레이 버퍼 경고**<br>*(`REG_WAIT timeout in dcn31_program_compbuf_size`)* | `amdgpu.sg_display=0`이 실제 적용됐는데도 현재 Linux 7.2.3 부팅에서 timeout이 한 번 남았음. GPU 리셋은 없었고 도크 A/B 시험도 아직 완료하지 않음. | **미해결; 시험 목적으로 `amdgpu.sg_display=0` 유지**<br>이 옵션이 경고를 해결한다고 더는 주장하지 않음. 옵션을 켠 상태와 끈 상태의 도크 반복 시험이 남아 있음. |
| **eDP 패널 PSR 불안정**<br>*(화면 전환 시 점멸·검은 화면)* | DCN 3.1.4의 eDP PSR 전력 상태 전환이 GPU 클럭 변경과 겹칠 수 있음. | **`amdgpu.dcdebugmask=0x10`**<br>PSR을 비활성화해 내부 패널 링크 상태 변화를 줄임. |
| **3D / Proton 실행 안정성** | 통합 GPU와 NVMe가 시스템 메모리 대역폭을 공유하므로 3D 초기화 때 IOMMU 변환 부하가 커질 수 있음. 이 기체의 과거 강제 재부팅 원인을 특정 오류 하나로 단정할 로그는 없음. | **`iommu=pt`**<br>통합 장치의 IOMMU 변환 오버헤드를 줄이는 보수적 설정. |
| **PCIe 링크 전력 상태 전환** | `pcie_aspm=off`가 적용된 현재 읽기 시험에서는 AER·NVMe 오류가 없었음. ASPM을 켠 대조 시험은 아직 없어 기존의 전압 강하 설명은 입증되지 않음. | **시험 목적으로 `pcie_aspm=off` 유지**<br>현재 안정성 기준에서 링크 전력 전환을 제외함. A/B 시험이 필요하며 ASPM 비활성화는 대기 전력을 높일 수 있음. |
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

지속 `O_DIRECT` 읽기 시험에서는 속도 제한 없이 3.5–3.9GiB/s가 유지됐고 NVMe/AER 오류는 없었지만, 컨트롤러는 81–82°C까지 상승했습니다. APST 수정은 대기·간헐 부하의 낭비를 줄이며 지속 풀로드 발열 자체를 없애지는 않습니다. 자세한 통과 항목과 남은 시험은 [실기 테스트 결과](docs/TEST_RESULTS.md)에 기록합니다.

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
1. **HHD 단독 관리**: TDP·컨트롤러 관리자를 하나만 유지하고 시스템·사용자 SteamOS Manager를 모두 마스크합니다. 선택된 지속 TDP는 보존하고 QAM boost를 끄며, 100% 자동 바이패스 정책을 설치합니다.
2. **안전 백업**: `/etc/default/limine`을 `/etc/default/limine.orig`로 자동 백업합니다.
3. **커널 파라미터 주입**: `acpi=strict`, `processor.max_cstate=1`, `idle=nomwait`, `nvme_core.default_ps_max_latency_us=15000`, `tsc=reliable`, `amdgpu.sg_display=0`, `amdgpu.dcdebugmask=0x10`, `iommu=pt`, `pcie_aspm=off`를 부트로더에 안전하게 추가하고 무효 파라미터(`amdgpu.gfxoff=0`)를 정리합니다.
4. **스케줄러 안정화**: 실험적인 BPF CPU 스케줄러(`scx_loader`)를 비활성화하고 원상 복구를 위해 기존 활성 상태를 기록합니다.
5. **하드웨어 udev 룰 등록**: 조이스틱 LED 절전 자동 소등 룰을 시스템에 등록합니다. (터치스크린 가로 보정은 컴포지터가 자체 처리하므로 룰을 별도로 설치하지 않습니다.)
6. **부트로더 갱신**: `limine-update`를 실행하여 새로운 커널 설정과 initramfs를 빌드합니다.
7. **NVMe 전력 관리**: 실행 중인 컨트롤러의 PM QoS도 15ms로 즉시 갱신하고, 구버전의 `ayaneo-nvme-guard`와 `app.slice` 쓰기 제한을 제거합니다.

---

## ↩️ 원상 복구 (제거 방법)

레포가 설치한 Limine 옵션, udev 규칙과 구버전 NVMe 제한을 제거하려면 아래 명령어를 실행합니다. HHD가 실행 중이면 컨트롤러와 전력 관리가 끊기지 않도록 HHD 및 충돌 서비스 마스크는 유지합니다.

```bash
cd ayaneo-slide-linux-fixes
sudo bash uninstall.sh
sudo systemctl reboot
```

현재 설치기는 자신이 새로 추가한 Limine 옵션을 기록하며, 제거할 때 그 옵션만 지워 설치 이후 사용자가 바꾼 항목을 보존합니다. 예전 `.orig` 파일은 수동 복구용으로 남기고 제거 스크립트가 통째로 덮어쓰지 않습니다.

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
| **fTPM** | **기본값 유지** | Enabled | 현재 수집한 로그에는 fTPM 오류가 없습니다. 디스크 암호화나 장치 인증에 사용할 수 있으므로 실제 fTPM 스터터가 재현될 때만 변경합니다. |
| **Core Watchdog Timer** | **기본값 유지** | Enabled | 현재의 CF9 리셋 기록만으로 워치독 오작동을 입증할 수 없습니다. 원인 분리 시험 없이 끄지 않습니다. |
| **IGD - AmdGop Output Priority** | **`LCD`** | CRT | 내부 디스플레이를 최우선 출력으로 지정하여 독(Dock) 연결이나 외부 디스플레이 분리 시 화면이 안 나오는 버그를 방지합니다. |

> 상세한 바이오스 설정 안내는 [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) 문서를 참고하세요.

---

## 🔋 추천 TDP 전력 프로필 (Decky Loader 활용)

| 용도 | TDP | Boost | GPU |
|---|---:|---|---|
| 가벼운 게임 / 최대 배터리 | 8–10W | 끔 | Auto |
| **슬라이드 안정성 시작점** | **12W** | **끔** | **Auto** |
| 7840U 일반 전성비 목표 | 15W | 끔 | Auto |
| CPU 의존 에뮬레이터 | 12–15W | 켜고/끄고 비교 | Auto |

Boost를 켜도 전력이 끝없이 올라가지는 않습니다. 실측한 8W 프로필에서는 HHD의 단기 Fast/Slow 한도가 10W로 올라가고 지속 한도는 8W로 남았습니다. Boost를 끄면 Fast/Slow/Skin/STAPM이 모두 8W가 됐습니다. CPU와 Radeon 780M이 같은 패키지 전력을 공유하므로 GPU 제한 게임에서는 CPU boost가 GPU의 전력·열 여유를 가져갈 수 있습니다. CPU 의존 작업에서 실제 성능이 좋아질 때만 켭니다.

현재 기체는 **12W, boost off**입니다. Space Marine 2처럼 과거에 약 5분 만에 시스템이 꺼진 부하를 12W에서 20–30분 통과한 뒤에만 15W로 올립니다. 실측 동작과 명령은 [TDP·Boost·충전 바이패스](docs/POWER_AND_CHARGING.md)에 정리했습니다.

고부하 게임은 **30 FPS 제한**부터 시작하고 안정적으로 유지되는 게임만 40 FPS로 올립니다. 일정한 제한은 표시 목표를 계속 놓치는 프레임을 만들기 위해 APU가 전력을 낭비하는 것을 줄입니다.

## 🔌 충전 제한 미지원 — 바이패스만 가능

이 기체에는 **충전 제한 옵션이 없습니다.** HHD 로그도 `Battery Limit` 경로를 찾지 못했고, 펌웨어가 `charge_control_end_threshold`를 제공하지 않으므로 80% 같은 상한값을 지정할 수 없습니다.

이와 별개로 Charge Bypass만 `disabled`와 `always` 두 상태로 동작합니다. 현재 `always` 상태는 Linux에서 `auto [inhibit-charge]`로 확인됩니다. 이것은 현재 잔량에서 충전을 막는 스위치이지 퍼센트를 지정하는 충전 제한 기능이 아닙니다. 여기서 선택되지 않은 `auto`는 커널이 일반 충전 모드에 붙인 이름이며, HHD가 잔량에 따라 자동 전환한다는 뜻이 아닙니다.

**100%에서 바이패스하는 것은 가능합니다.** 현재 기체도 `capacity=100`, `status=Full`, HHD `always`, 커널 `inhibit-charge`로 이미 충전 억제 중입니다. 이후 99%로 떨어져도 `always`인 동안에는 자동 보충 충전을 하지 않으며, 다시 충전하려면 `disabled`로 바꿔야 합니다. 보충 충전은 막지만 배터리를 100% 고전압 상태에서 내려주지는 않습니다.

설치기는 히스테리시스를 두어 이를 자동화합니다. 30초마다 확인해 **100%에서 `always`**로 전환하고, **96–99%에서는 현재 상태를 유지**하며, **95% 이하에서 `disabled`**로 충전을 재개합니다. 따라서 99↔100% 보충 충전을 반복하지 않으며, 실제 상태를 바꿀 때만 HHD를 호출합니다.

자동 정책이 바이패스 상태를 관리하므로 임의 잔량인 80%를 동시에 유지할 수는 없습니다. 80% 근처를 수동으로 유지하려면 먼저 `ayaneo-charge-at-full.timer`를 끄고, 전원을 뽑아 80%까지 사용한 다음 `always`를 선택하고 다시 연결합니다. 바이패스는 현재 잔량에서 충전을 막을 뿐, 연결된 상태에서 100% 배터리를 80%까지 능동 방전시키지는 않습니다.

---

## 🔍 패치 정상 적용 여부 확인 방법

재부팅 후 터미널에서 다음 명령어들로 설치된 설정을 확인할 수 있습니다:

```bash
# 1. 커널 부팅 파라미터 확인
cat /proc/cmdline
# 확인: acpi=strict, processor.max_cstate=1, idle=nomwait, nvme_core.default_ps_max_latency_us=15000 포함 여부

# 2. C-state 제한 확인 (POLL과 C1만 보여야 함)
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

# 5. HHD TDP, boost, 충전 바이패스 확인
HHDCTL="$HOME/.local/share/hhd/venv/bin/hhdctl"
"$HHDCTL" get tdp.qam.tdp tdp.qam.boost tdp.battery.charge_bypass
cat /sys/class/power_supply/BAT0/charge_behaviour
# 현재 기체: 12, false, always / 커널: auto [inhibit-charge]

systemctl is-enabled ayaneo-charge-at-full.timer
systemctl status ayaneo-charge-at-full.timer --no-pager
# 설치 후: enabled / active (waiting)
```

---

## 📚 기술 문서 링크

* [docs/HARDWARE_ANALYSIS.md](docs/HARDWARE_ANALYSIS.md) — 실측 NVMe 전력 상태, HMB, 온도, 재부팅 로그와 컨트롤러 스택 분석
* [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md) — 재부팅, APST, HMB, 슬립 복귀, 직접 읽기 부하 시험 및 알려진 한계
* [docs/POWER_AND_CHARGING.md](docs/POWER_AND_CHARGING.md) — TDP 프로필, boost 동작, 충전 제한 미지원과 2상태 바이패스
* [docs/BIOS_RECOMMENDATIONS.md](docs/BIOS_RECOMMENDATIONS.md) — 바이오스 최적화 단계별 가이드
* [README.md](README.md) — Global English Documentation

---

## 🤝 참고 문헌 및 커뮤니티 기여

* [ChimeraOS Issue #892](https://github.com/ChimeraOS/chimeraos/issues/892) — 아야네오 슬라이드 / Antec Core HS의 `acpi=strict` 해결책 발견
* [Valve Software SteamOS Issue #2757](https://github.com/ValveSoftware/SteamOS/issues/2757) — AMD 플랫폼 리셋 관련 커뮤니티 조사
* [Bazzite Issue #5596 & #5508](https://github.com/ublue-os/bazzite/issues/5596) — 슬라이드 절전 루틴 및 입력 장치 분석
* [ShadowBlip / ayaneo-platform](https://github.com/ShadowBlip/ayaneo-platform) — 아야네오 리눅스 커널 플랫폼 드라이버

---

## 📜 라이선스

이 프로젝트는 [MIT License](LICENSE) 하에 자유롭게 수정 및 배포가 가능합니다. 버그 리포트와 풀 리퀘스트(PR)는 언제나 환영합니다!
