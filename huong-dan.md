# Hướng dẫn chi tiết — WinVM Codespaces VIP

Tài liệu này hướng dẫn từng bước chạy Windows 10 Pro, Windows 11 Pro,
Windows 11 Enterprise LTSC 2024 (eval) hoặc Windows Server 2022
(Desktop Experience) trong GitHub Codespaces bằng QEMU + noVNC.

> **Cảnh báo quan trọng**
>
> - GitHub Codespaces **không có `/dev/kvm`**. QEMU phải giả lập CPU bằng
>   TCG, nên Windows chạy **chậm hơn máy thật rất nhiều**. Boot có thể mất
>   10–30 phút, cài đặt lần đầu có thể lâu hơn.
> - Chỉ dùng cho học tập, phát triển và thử nghiệm. Không dùng Codespaces
>   làm server 24/7, không chạy tải nặng kéo dài, không vi phạm
>   [GitHub Acceptable Use Policies](https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies).
> - Windows là phần mềm có bản quyền. Script chỉ tải ISO chính thức từ
>   Microsoft; bạn tự chịu trách nhiệm về bản quyền và kích hoạt.

## 1. Yêu cầu

- GitHub Codespaces với máy **4 core / 16 GB RAM** trở lên.
  Khuyến nghị 8 core / 32 GB nếu muốn chạy nhiều máy ảo.
- Còn trống ít nhất **25 GB** trong workspace cho một Windows.
- Trình duyệt hiện đại để mở noVNC.
- Tài khoản GitHub có quyền tạo Codespaces.

Kiểm tra tài nguyên trong Codespaces:

```bash
nproc
free -h
df -h .
```

## 2. Mở dự án trong Codespaces

1. Đưa thư mục `winvm-codespaces-vip` vào một repository GitHub.
2. Chọn **Code → Codespaces → Create codespace on main**.
3. Chờ `postCreateCommand` chạy `bash scripts/setup.sh`.
   Nếu chưa tự chạy, mở terminal và chạy tay:

```bash
bash scripts/setup.sh
```

Script cài QEMU, OVMF, swtpm, genisoimage, noVNC, websockify,
PowerShell 7, `zip`, `shellcheck` và các công cụ cần thiết.

Kiểm tra nhanh:

```bash
qemu-system-x86_64 --version
command -v websockify
bash scripts/status.sh
```

## 3. Chuẩn bị ISO Windows

Chọn một cách:

### Cách A — tải bằng script (khuyến nghị)

```bash
bash scripts/fetch-iso.sh win11-ltsc     # dễ nhất, link eval chính thức
bash scripts/fetch-iso.sh server2022
bash scripts/fetch-iso.sh win11
bash scripts/fetch-iso.sh win10
```

- `win11-ltsc` và `server2022` dùng link eval chính thức của Microsoft,
  thường tải được ngay.
- `win11` dùng Fido để lấy link Pro; một số IP bị Microsoft Sentinel chặn.
  Khi đó dùng `win11-ltsc`, hoặc tải ISO trên PC rồi upload.
- `win10` không có link trực tiếp ổn định; nên tải trên PC rồi upload,
  hoặc truyền `--url`.

Chi tiết nguồn ISO, edition index và cách upload: [iso.md](iso.md).

### Cách B — upload ISO có sẵn

Trong VS Code/Codespaces, kéo file ISO vào thư mục `iso/`, hoặc dùng
`gh codespace cp` từ máy local:

```bash
gh codespace cp ./Win11_24H2_Vietnamese_x64.iso remote:~/winvm-codespaces-vip/iso/win11.iso
```

Đặt đúng tên để script tự tìm:

| OS | Tên gợi ý |
| --- | --- |
| Windows 10 Pro | `iso/win10.iso` |
| Windows 11 Pro | `iso/win11.iso` |
| Windows 11 LTSC 2024 | `iso/win11-ltsc.iso` |
| Windows Server 2022 | `iso/server2022.iso` |

Script cũng quét các mẫu tên như `Win11*.iso`, `*LTSC*.iso`,
`*Server*2022*.iso`.

### Cách C — truyền URL trực tiếp

```bash
bash scripts/fetch-iso.sh win11 --url "https://example.com/duong-dan/Win11.iso"
```

Chỉ dùng URL tin cậy. Không dùng ISO đã bị chỉnh sửa từ nguồn lạ.

## 4. Tạo máy ảo

```bash
bash scripts/create-vm.sh win11
```

Tùy chọn:

```bash
bash scripts/create-vm.sh win11 --disk-gb 50 --ram-mb 6144 --cpus 4
bash scripts/create-vm.sh win11 --dry-run   # chỉ in kế hoạch
```

Mặc định:

- Disk qcow2 40 GB (Server 2022: 32 GB), gắn qua AHCI (q35).
- NIC Intel e1000, dùng driver có sẵn trong Windows.
- RAM 4096 MB, tự tăng lên 6144 MB nếu host có từ 16 GB.
- vCPU tối đa 4.
- UEFI/OVMF, tools ISO chứa `autounattend.xml` và script guest.
- ISO được kiểm tra volume label để tránh cài nhầm edition.

Lệnh này tạo:

```
vm/<os>/disk.qcow2      # ổ đĩa Windows
vm/<os>/OVMF_VARS.fd    # biến UEFI
vm/<os>/tools.iso       # autounattend + script tiếng Việt
vm/<os>/vm.conf         # cấu hình
```

## 5. Bật máy ảo và mở noVNC

```bash
bash scripts/run-vm.sh win11
```

Script khởi động:

- QEMU với `-accel tcg,thread=multi` (hoặc KVM nếu máy có `/dev/kvm`).
- swtpm cho Windows 11 (TPM 2.0 ảo).
- websockify/noVNC ở cổng **6080**.

Mở tab **Ports** trong Codespaces → cổng **6080** → **Open in Browser**.
Link có dạng:

```
https://<codespace-name>-6080.<domain>/vnc.html?autoconnect=true&resize=scale
```

Hoặc lấy link bằng:

```bash
bash scripts/manage.sh url
```

Menu tổng hợp:

```bash
bash scripts/boot-menu.sh
```

## 6. Quá trình cài Windows

Windows Setup sẽ tự động:

1. Chọn đúng edition (Pro / LTSC / Server Desktop Experience).
2. Xóa và phân vùng ổ đĩa ảo.
3. Cài Windows, bỏ qua kiểm tra TPM/Secure Boot/RAM/CPU nếu cần.
4. Tạo tài khoản `VIP`, tự đăng nhập.
5. Chạy `C:\Windows\Setup\Scripts\setup-win.ps1` ở lần đăng nhập đầu.

Các bước guest:

| Bước | Việc |
| --- | --- |
| `install-vi.ps1` | Cài `vi-VN`, bàn phím Telex, múi giờ Việt Nam |
| `install-mesa.ps1` | Mesa OpenGL + Vulkan lavapipe + anti-lag |
| `install-vulkan.ps1` | Vulkan Runtime chính thức của LunarG |
| `install-dxvk.ps1` | Tải DXVK vào `C:\VIP\DXVK` |
| `optimize.ps1` | Tối ưu chống lag, có backup để hoàn tác |
| `boot-vip.ps1` | Fast startup, boot menu, wallpaper VIP |

Log đầy đủ:

```
C:\VIP\setup.log
```

Nếu bước nào lỗi (thường do mạng trong VM chưa sẵn sàng), setup kiểm tra
mạng nhanh, bỏ qua bước tải nặng, ghi lỗi vào log và để note trên desktop
`WINVM-VIP-DOC-TRUOC.txt`. Các bước cần làm tay nằm trong
`C:\VIP\manual-steps.txt`. Vào Windows rồi chạy lại:

```powershell
# Thay win11 bằng win10, win11-ltsc hoặc server2022 cho đúng edition.
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\setup-win.ps1 -OS win11
```

## 7. Tài khoản mặc định

| Mục | Giá trị |
| --- | --- |
| User | `VIP` |
| Password | `Vip@2026` |
| Quyền | Administrator |
| Máy | `WINVM-VIP` |

**Đổi mật khẩu ngay** trong PowerShell của Windows:

```powershell
net user VIP "MatKhauMoiCuaBan"
```

Menu tiện ích trong Windows: shortcut **VIP Tools** trên desktop, hoặc:

```powershell
powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\vip-tools.ps1
```

## 8. Kết nối RDP (tùy chọn)

QEMU forward `localhost:3389` của Codespaces vào `3389` của Windows.
Bật Remote Desktop trong Windows trước, sau đó forward cổng:

```bash
gh codespace ports forward 3389:3389 -c <codespace-name>
```

Kết nối RDP client tới `localhost:3389`, user `VIP`.

Nếu chỉ cần xem màn hình, noVNC nhẹ và ổn định hơn RDP trong Codespaces.

## 9. Snapshot và khôi phục

Phải tắt máy ảo trước:

```bash
bash scripts/stop-vm.sh win11
bash scripts/snapshot.sh win11 create truoc-khi-cai-game
bash scripts/snapshot.sh win11 list
bash scripts/snapshot.sh win11 restore truoc-khi-cai-game
```

Snapshot lưu bên trong file qcow2, không tốn thêm file lớn bên ngoài.
Dung lượng thực tế của qcow2 sẽ tăng theo dữ liệu đã ghi.

## 10. Tắt máy và dữ liệu

```bash
bash scripts/stop-vm.sh win11
```

Script gửi ACPI shutdown, chờ Windows tắt an toàn (mặc định 120 giây),
sau đó mới kill QEMU. Không kill QEMU đột ngột nếu đang ghi dữ liệu.

- Disk và snapshot nằm trong `vm/<os>/`, thuộc workspace Codespaces.
- Khi Codespaces stop/restart, VM **không tự chạy lại**; chỉ cần
  `bash scripts/run-vm.sh <os>`.
- Xóa Codespaces sẽ xóa toàn bộ disk nếu bạn không backup.

Backup disk:

```bash
bash scripts/stop-vm.sh win11
cp vm/win11/disk.qcow2 /tmp/disk-backup.qcow2
```

## 11. Hiệu năng và giới hạn

- TCG giả lập CPU: chậm, tốn CPU host, không hợp cho game nặng.
- Mesa là GPU phần mềm; Vulkan lavapipe và DXVK cũng chạy bằng CPU.
- DXVK chỉ giúp chuyển Direct3D sang Vulkan; không biến CPU thành GPU.
- Không nên chạy nhiều VM cùng lúc trên một Codespaces 4 core.
- Codespaces có giới hạn thời gian và băng thông; xem tài liệu GitHub.

Nếu cần hiệu năng thật, chạy bộ script này trên máy Linux có `/dev/kvm`
(máy local, server riêng, Google Colab có KVM...). Script tự phát hiện KVM.

## 12. Dọn dẹp và làm lại

Tắt máy ảo rồi xóa thư mục VM:

```bash
bash scripts/stop-vm.sh win11
rm -rf vm/win11
bash scripts/create-vm.sh win11
```

Xóa ISO không dùng:

```bash
rm -f iso/win10.iso
```

Kiểm tra dung lượng:

```bash
du -sh iso vm
df -h .
```

## 13. Cấu trúc dự án

```
winvm-codespaces-vip/
├── .devcontainer/          # cấu hình Codespaces
├── scripts/                # script host (Linux/Codespaces)
├── guest/                  # autounattend + PowerShell trong Windows
├── tests/                  # test host
├── docs/                   # tài liệu
├── iso/                    # ISO (không commit)
├── vm/                     # disk, tools.iso, log (không commit)
├── pack.sh                 # đóng gói zip vào /sdcard/Download
└── README.md
```

## 14. Đóng gói để tải về

```bash
bash pack.sh
```

Tạo:

```
/sdcard/Download/winvm-codespaces-vip.zip
/sdcard/Download/winvm-codespaces-vip.zip.sha256.txt
```

File zip không chứa `iso/`, `vm/`, `.git/`, `.tools/`, `.superpowers/`,
`docs/superpowers/`, log hay pid.

Kiểm tra:

```bash
cd /sdcard/Download
sha256sum -c winvm-codespaces-vip.zip.sha256.txt
unzip -t winvm-codespaces-vip.zip
```

## 15. Gặp lỗi?

Xem [loi-thuong-gap.md](loi-thuong-gap.md). Khi báo lỗi, gửi kèm:

- Output của `bash scripts/status.sh`
- `vm/<os>/qemu-launch.log`
- `vm/<os>/websockify.log`
- `C:\VIP\setup.log` (trong Windows)
- Phiên bản QEMU: `qemu-system-x86_64 --version`
