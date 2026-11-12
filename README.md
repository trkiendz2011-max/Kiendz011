# WinVM Codespaces VIP

Bộ script tạo máy ảo **Windows 10 Pro / Windows 11 Pro / Windows 11 Enterprise LTSC 2024 / Windows Server 2022** ngay trong **GitHub Codespaces** bằng QEMU, xem qua trình duyệt bằng noVNC.

Bản VIP gồm:

- Menu boot VIP trong terminal, chọn Windows 10 / 11 / 11 LTSC / Server 2022.
- Cài tự động, không cần bấm Next từng bước.
- Tiếng Việt: locale `vi-VN`, bàn phím Telex, múi giờ Việt Nam.
- GPU ảo Mesa (OpenGL software + Vulkan lavapipe) cho máy ảo.
- Vulkan runtime + DXVK để chạy game Direct3D qua Vulkan.
- Tối ưu chống lag: power plan, tắt telemetry, giảm hiệu ứng, giảm delay mạng/chuột.
- Boot nhanh: fast startup, boot timeout 3 giây, bỏ delay khởi động.
- Kiểm tra ISO đúng edition trước khi tạo disk, tránh cài nhầm Windows.
- Toàn bộ script và hướng dẫn nằm trong một thư mục, có thể tải về máy.

> **Đọc trước khi làm:** GitHub Codespaces **không bật KVM**, nên QEMU phải giả lập CPU bằng TCG. Windows sẽ **chậm** — boot có thể 10–30 phút, desktop dùng được nhưng không mượt như PC thật. Mesa/Vulkan trong máy ảo cũng là giả lập phần mềm. Nếu cần nhanh, hãy chạy bộ script này trên máy Linux có `/dev/kvm` (máy local, server riêng, Google Colab có KVM...). Script tự dùng KVM khi có.

> **Trách nhiệm:** Chỉ dùng cho học tập/dev. Không dùng Codespaces làm server 24/7, không vi phạm Acceptable Use của GitHub. Windows là phần mềm có bản quyền; script chỉ tải ISO từ Microsoft, bạn tự chịu trách nhiệm kích hoạt/bản quyền.

## Yêu cầu

- GitHub Codespaces máy **4 core / 16 GB RAM** trở lên (khuyến nghị 8 core / 32 GB nếu muốn để nhiều ISO).
- Ổ đĩa còn trống ít nhất **25 GB** cho một Windows.
- Trình duyệt để mở noVNC.

## Bắt đầu nhanh

```bash
# 1. Cài QEMU, OVMF, swtpm, noVNC, PowerShell 7
bash scripts/setup.sh

# 2. Tải ISO (chọn 1 trong 4)
bash scripts/fetch-iso.sh win11-ltsc   # dễ nhất, link eval chính thức
bash scripts/fetch-iso.sh server2022
bash scripts/fetch-iso.sh win11
bash scripts/fetch-iso.sh win10

# Hoặc tự tải ISO trên PC rồi upload vào thư mục iso/
#    iso/win10.iso, iso/win11.iso, iso/win11-ltsc.iso, iso/server2022.iso

# 3. Tạo máy ảo
bash scripts/create-vm.sh win11

# 4. Bật máy ảo + noVNC
bash scripts/run-vm.sh win11
```

Sau khi chạy, mở tab **Ports** của Codespaces, chọn cổng **6080** → **Open in Browser**. Đó là màn hình Windows.

Nếu muốn menu tiện dụng:

```bash
bash scripts/boot-menu.sh
```

## Tài khoản Windows mặc định

| Mục | Giá trị |
| --- | --- |
| User | `VIP` |
| Password | `Vip@2026` |
| Quyền | Administrator |
| Tên máy | `WINVM-VIP` |

**Đổi mật khẩu ngay** sau khi vào Windows:

```powershell
net user VIP "MatKhauMoiCuaBan"
```

## Lệnh thường dùng

| Lệnh | Việc |
| --- | --- |
| `bash scripts/setup.sh` | Cài dependency trên Codespaces |
| `bash scripts/fetch-iso.sh <os>` | Tải ISO chính thức từ Microsoft |
| `bash scripts/create-vm.sh <os>` | Tạo disk + tools ISO + cấu hình |
| `bash scripts/run-vm.sh <os>` | Bật VM và noVNC |
| `bash scripts/stop-vm.sh <os>` | Tắt VM an toàn |
| `bash scripts/status.sh` | Xem VM nào đang chạy, disk, RAM, accel |
| `bash scripts/snapshot.sh <os> create <ten>` | Tạo snapshot |
| `bash scripts/snapshot.sh <os> list` | Liệt kê snapshot |
| `bash scripts/snapshot.sh <os> restore <ten>` | Khôi phục snapshot |
| `bash scripts/boot-menu.sh` | Menu VIP đầy đủ |
| `bash pack.sh` | Đóng gói zip vào `/sdcard/Download` |

`<os>` là một trong `win10`, `win11`, `win11-ltsc`, `server2022`.

## Lần đầu Windows khởi động

Windows Setup sẽ tự:

1. Cài đúng edition (Pro / LTSC / Server Desktop Experience).
2. Tạo user `VIP`, tự đăng nhập.
3. Chạy `setup-win.ps1` ở lần đăng nhập đầu tiên:
   - Cài tiếng Việt + bàn phím Telex + múi giờ.
   - Cài Mesa3D (OpenGL + Vulkan lavapipe).
   - Cài Vulkan runtime + DXVK.
   - Tối ưu chống lag (có backup để hoàn tác).
   - Bật fast startup, boot VIP, wallpaper VIP.
4. Ghi log vào `C:\VIP\setup.log`.
5. Tạo shortcut **VIP Tools** trên desktop.

Nếu mạng trong máy ảo chưa có, setup kiểm tra nhanh rồi bỏ qua các bước
tải nặng, ghi lỗi vào `C:\VIP\setup.log` và để note trên desktop
`WINVM-VIP-DOC-TRUOC.txt`. Bạn có thể chạy lại sau:

```powershell
# Thay win11 bằng win10, win11-ltsc hoặc server2022 cho đúng edition.
powershell -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\setup-win.ps1 -OS win11
```

## Cấu trúc

```
winvm-codespaces-vip/
├── .devcontainer/devcontainer.json
├── scripts/        # host scripts (Codespaces/Linux)
├── guest/          # autounattend + PowerShell chạy trong Windows
├── tests/          # test host scripts
├── docs/           # hướng dẫn, ISO, lỗi thường gặp
├── iso/            # đặt ISO vào đây (không commit)
├── vm/             # disk, tools.iso, log (không commit)
└── pack.sh         # đóng gói zip + sha256 vào /sdcard/Download
```

## Đóng gói để tải về

```bash
bash pack.sh
```

Kết quả:

```
/sdcard/Download/winvm-codespaces-vip.zip
/sdcard/Download/winvm-codespaces-vip.zip.sha256.txt
```

File zip không chứa `iso/`, `vm/`, `.git/`, `.tools/`, `.superpowers/`,
`docs/superpowers/`, log hay pid.

## Tài liệu

- [Hướng dẫn chi tiết](docs/huong-dan.md)
- [Nguồn ISO hợp pháp](docs/iso.md)
- [Lỗi thường gặp](docs/loi-thuong-gap.md)

## Giấy phép

Script trong repo này dùng cho mục đích học tập. Windows, Mesa3D, DXVK, Vulkan Runtime và các thành phần khác giữ bản quyền/giấy phép riêng của chúng.
