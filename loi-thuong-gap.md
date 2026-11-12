# Lỗi thường gặp và cách xử lý

## 1. Windows chạy rất chậm

**Triệu chứng:** Boot lâu, chuột/desktop giật, cài đặt hàng chục phút.

**Nguyên nhân:** GitHub Codespaces không có `/dev/kvm`; QEMU dùng TCG để
giả lập CPU. Mesa, Vulkan lavapipe và DXVK đều chạy bằng CPU.

**Cách xử lý:**

- Kiên nhẫn ở lần cài đầu; sau khi cài xong và snapshot, lần sau nhanh hơn.
- Giảm RAM/CPU nếu host thiếu tài nguyên, hoặc tăng nếu host còn trống.
- Không chạy nhiều VM cùng lúc.
- Dùng máy có KVM nếu cần hiệu năng thật:

```bash
ls -l /dev/kvm
bash scripts/status.sh
```

Nếu `/dev/kvm` tồn tại, script tự dùng KVM.

## 2. `Chưa có ISO cho ...`

**Triệu chứng:**

```
[X] Chưa có ISO cho Windows 11 Pro. Đặt file vào .../iso/win11.iso
```

**Cách xử lý:**

```bash
ls -lh iso/
bash scripts/fetch-iso.sh win11-ltsc
```

Hoặc upload ISO và đặt đúng tên. Kiểm tra script có tìm thấy không:

```bash
ISO_DIR="$PWD/iso" bash -c 'source scripts/common.sh; find_iso win11'
```

## 3. Fido / Microsoft Sentinel chặn lấy link ISO

**Triệu chứng:** `fetch-iso.sh win11` báo lỗi, hoặc test dry-run bị SKIP.

**Nguyên nhân:** Microsoft Sentinel chặn IP của Codespaces khi tra link
Windows 11/10 Pro.

**Cách xử lý:**

- Dùng bản eval chính thức:

```bash
bash scripts/fetch-iso.sh win11-ltsc
bash scripts/fetch-iso.sh server2022
```

- Tải ISO trên PC rồi upload.
- Truyền link trực tiếp bằng `--url`.
- Thử lại sau vài giờ hoặc dùng mạng khác.

## 3b. ISO sai edition

**Triệu chứng:**

```text
[X] ISO không phải Windows 11 Enterprise LTSC 2024 (eval)
    (volume: 'CCCOMA_X64FRE_EN-US_DV9').
```

**Nguyên nhân:** File ISO là bản Windows 11 thường (Home/Pro), không phải
LTSC. Image index 1 của bản thường không phải LTSC, nên cài sẽ sai edition.

Lưu ý: ISO LTSC 2024 eval chính thức của Microsoft có volume label
`CESE_X64FREE_EN-US_DV9`; ISO Server 2022 eval có label
`SSS_X64FREE_EN-US_DV9`. Hai label này không chứa chữ `LTSC`/`SERVER`
nhưng vẫn được chấp nhận đúng edition.

**Cách xử lý:**

```bash
ls -lh iso/
bash scripts/fetch-iso.sh win11-ltsc
```

Hoặc đặt đúng file `iso/win11-ltsc.iso`. Với Server 2022, dùng ISO có
volume label chứa `SERVER` hoặc bắt đầu bằng `SSS_` (bản eval chính thức).
Với Win10/Win11 Pro, không dùng ISO Server/LTSC/eval.

Chỉ dùng `VIP_SKIP_ISO_CHECK=1` khi bạn chắc chắn về ISO đặc biệt:

```bash
VIP_SKIP_ISO_CHECK=1 bash scripts/create-vm.sh win11
```

## 4. Cổng 6080 đang bận

**Triệu chứng:**

```
[X] Cổng 6080 đang bận. Tắt tiến trình đang dùng cổng rồi thử lại.
```

**Cách xử lý:**

```bash
ss -ltnp | grep 6080
pkill -f websockify
bash scripts/stop-vm.sh win11
bash scripts/run-vm.sh win11
```

Đổi cổng nếu cần:

```bash
VNC_PORT=6081 bash scripts/run-vm.sh win11
```

Nhớ mở đúng cổng mới trong tab Ports.

## 5. noVNC trắng hoặc không kết nối

**Kiểm tra:**

```bash
bash scripts/status.sh win11
cat vm/win11/websockify.log
ps -ef | grep -E 'qemu|websockify'
ss -ltn | grep 6080
```

**Cách xử lý:**

- Chắc chắn QEMU còn chạy (pid trong `vm/win11/qemu.pid`).
- Mở đúng link `.../vnc.html?autoconnect=true&resize=scale`.
- Trong Codespaces, tab **Ports** phải forward cổng 6080.
- Nếu websockify chết, chạy lại `run-vm.sh` sau khi `stop-vm.sh`.
- Thử tắt VPN/proxy chặn WebSocket.

## 6. QEMU không khởi động

**Xem log:**

```bash
cat vm/win11/qemu-launch.log
```

**Lỗi thường gặp:**

| Lỗi | Cách xử lý |
| --- | --- |
| `Could not access KVM kernel module` | Không có KVM; đặt `ACCEL=tcg,thread=multi` |
| `No 'usb-bus' bus found` | Bản cũ thiếu `-usb`; cập nhật script |
| `Could not open ... OVMF_VARS.fd` | Chạy lại `create-vm.sh` để tạo biến UEFI |
| `Failed to get "write" lock` | VM khác đang dùng disk; tắt VM cũ |
| `No space left on device` | Xóa ISO/VM/snapshot không dùng |

Kiểm tra disk:

```bash
df -h .
qemu-img info vm/win11/disk.qcow2
```

## 7. Lỗi TPM / swtpm với Windows 11

**Triệu chứng:** QEMU báo lỗi socket TPM, hoặc Windows Setup báo thiếu TPM.

**Cách xử lý:**

```bash
command -v swtpm
bash scripts/setup.sh
ls -l vm/win11/tpm/
cat vm/win11/swtpm.log
```

Nếu TPM state hỏng và bạn chấp nhận cài lại Windows:

```bash
bash scripts/stop-vm.sh win11
rm -rf vm/win11/tpm
bash scripts/run-vm.sh win11
```

Autounattend đã có `BypassTPMCheck` và `BypassSecureBootCheck`; nếu vẫn
bị chặn, kiểm tra tools ISO có được gắn không:

```bash
ls -l vm/win11/tools.iso
```

## 8. Windows Setup không đọc autounattend

**Triệu chứng:** Setup dừng ở màn hình chọn ngôn ngữ/edition, hoặc không
tự tạo user `VIP`.

**Kiểm tra:**

- `vm/<os>/tools.iso` tồn tại và được gắn làm CD-ROM thứ hai.
- Trong ISO có `/autounattend.xml` và `/$OEM$/$$/Setup/Scripts/`.
- Chạy `run-vm.sh --dry-run` xem có `tools.iso` không.
- ISO Windows phải là bản chính thức, không bị chỉnh sửa.

Xem lại:

```bash
bash scripts/build-tools-iso.sh win11 vm/win11/tools.iso
isoinfo -J -f -i vm/win11/tools.iso | head -n 20
```

Nếu vẫn lỗi, cài tay một lần, sau đó chạy script trong Windows:

```powershell
# Thay win11 bằng win10, win11-ltsc hoặc server2022 cho đúng edition.
powershell -ExecutionPolicy Bypass -File D:\scripts\setup-win.ps1 -OS win11
```

## 9. Không cài được tiếng Việt

**Triệu chứng:** `C:\VIP\setup.log` ghi lỗi `Install-Language` hoặc DISM.

**Nguyên nhân:** Windows chưa có mạng, hoặc language pack không tải được.

**Cách xử lý trong Windows:**

```powershell
Test-NetConnection www.microsoft.com -Port 443
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-vi.ps1
```

Sau khi cài, đăng xuất/đăng nhập lại để giao diện đổi ngôn ngữ. Nếu vẫn
không có gói ngôn ngữ, vào **Settings → Time & Language → Language &
region → Add a language → Tiếng Việt**.

Script cũng ghi các bước thủ công vào `C:\VIP\manual-steps.txt` và desktop
`WINVM-VIP-DOC-TRUOC.txt`. Nếu máy ảo không có internet, setup sẽ bỏ qua
các bước tải nặng thay vì treo OOBE; mở desktop note để xem việc cần làm.

## 10. Mesa / OpenGL / Vulkan lỗi

**Xem log:**

```powershell
Get-Content C:\VIP\setup.log -Tail 100
```

**Kiểm tra file:**

```powershell
Test-Path C:\Windows\System32\opengl32.dll
Test-Path C:\Windows\System32\vulkan_lvp.dll
Test-Path C:\Windows\System32\lvp_icd.x86_64.json
```

**Cách xử lý:**

```powershell
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-mesa.ps1
```

- Cần mạng để tải Mesa từ GitHub.
- Cần đủ dung lượng `C:\VIP\downloads`.
- Nếu giải nén lỗi, kiểm tra `tar.exe` và `7zr.exe` trong `C:\VIP\tools`.
- Khôi phục file gốc: `restore-defaults.ps1`.

Lưu ý: Mesa là GPU phần mềm. Đừng kỳ vọng FPS cao.

## 11. Thiếu `vulkan-1.dll`

**Triệu chứng:** Game báo thiếu Vulkan loader, hoặc DXVK không chạy.

**Cách xử lý:**

```powershell
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-vulkan.ps1
Test-Path C:\Windows\System32\vulkan-1.dll
```

Script tải **Vulkan Runtime** chính thức của LunarG (~25 MB), chạy silent
`/S`. Nếu link tải lỗi, script thử `winget install KhronosGroup.VulkanRT`.

Cài tay:

```powershell
winget install --id KhronosGroup.VulkanRT -e
```

Khởi động lại Windows sau khi cài.

## 12. DXVK làm game crash hoặc không vào được

**Nguyên nhân:**

- Game dùng anti-cheat không hỗ trợ DXVK.
- Deploy nhầm bản 32-bit/64-bit.
- Game yêu cầu DirectX 12 (DXVK chủ yếu hỗ trợ D3D8/9/10/11).
- Thiếu Vulkan loader hoặc lavapipe.

**Cách xử lý:**

- Chỉ dùng DXVK với game single-player/offline.
- Kiểm tra kiến trúc game: `x64` hoặc `x86`.
- Deploy đúng thư mục game:

```powershell
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-dxvk.ps1 -GameDir "C:\Games\TenGame" -Arch x64
```

- Khôi phục DLL gốc trong `C:\VIP\backup\dxvk\<ten-game>`.
- Xóa `d3d11.dll`, `dxgi.dll` khỏi thư mục game nếu game không khởi động.

## 13. Tối ưu làm máy lạ hoặc mất tính năng

Chạy khôi phục:

```powershell
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\restore-defaults.ps1
```

Khởi động lại Windows. Script khôi phục registry, service, power plan và
file Mesa từ `C:\VIP\backup`.

## 14. Snapshot lỗi

**Triệu chứng:** `snapshot.sh` báo VM đang chạy hoặc không thấy snapshot.

**Cách xử lý:**

```bash
bash scripts/stop-vm.sh win11
bash scripts/snapshot.sh win11 list
bash scripts/snapshot.sh win11 create ten-moi
```

Tên snapshot phải đúng như trong `list`. Không tạo snapshot khi QEMU đang
chạy vì dễ hỏng disk.

## 15. RDP không kết nối

- Bật **Remote Desktop** trong Windows:

```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

- Forward cổng từ Codespaces:

```bash
gh codespace ports forward 3389:3389 -c <codespace-name>
```

- Kết nối `localhost:3389`, user `VIP`.
- Nếu không cần RDP, dùng noVNC cho đơn giản.

## 16. Codespaces restart làm mất VM?

Không mất disk nếu workspace còn. VM chỉ không tự chạy lại:

```bash
bash scripts/status.sh
bash scripts/run-vm.sh win11
```

Nếu đã xóa Codespaces, disk trong `vm/` cũng mất. Hãy backup qcow2 hoặc
snapshot ra ngoài trước.

## 17. Muốn xóa sạch làm lại

```bash
bash scripts/stop-vm.sh win11
rm -rf vm/win11
rm -f iso/win11.iso
bash scripts/fetch-iso.sh win11-ltsc
bash scripts/create-vm.sh win11-ltsc
bash scripts/run-vm.sh win11-ltsc
```

## 18. Nơi lấy log

| Log | Vị trí |
| --- | --- |
| QEMU launch | `vm/<os>/qemu-launch.log` |
| noVNC/websockify | `vm/<os>/websockify.log` |
| swtpm | `vm/<os>/swtpm.log` |
| Guest setup | `C:\VIP\setup.log` |
| Windows Setup | `C:\Windows\Panther\` |

Khi báo lỗi, gửi kèm các log trên và output:

```bash
bash scripts/status.sh
qemu-system-x86_64 --version
```
