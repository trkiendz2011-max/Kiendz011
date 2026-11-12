# Nguồn ISO hợp pháp và cách chuẩn bị

Chỉ tải ISO từ Microsoft hoặc nguồn chính thức mà bạn có quyền sử dụng.
Không dùng ISO "mod", "lite", "ghost" hoặc file không rõ nguồn gốc.

## 1. Bảng nhanh

| OS | Lệnh | Nguồn | Edition index |
| --- | --- | --- | --- |
| Windows 10 Pro | `bash scripts/fetch-iso.sh win10` | Fido (nếu được phép) hoặc upload tay | 6 |
| Windows 11 Pro | `bash scripts/fetch-iso.sh win11` | Fido + Microsoft | 6 |
| Windows 11 Enterprise LTSC 2024 (eval) | `bash scripts/fetch-iso.sh win11-ltsc` | Microsoft Evaluation Center | 1 |
| Windows Server 2022 (Desktop Experience) | `bash scripts/fetch-iso.sh server2022` | Microsoft Evaluation Center | 4 |

Edition index là thứ tự image trong file ISO. Autounattend dùng index này
để cài đúng bản. Nếu ISO của bạn có thứ tự khác, sửa `<Value>` trong
`guest/autounattend/<os>.xml` hoặc chọn index đúng.

## 2. Link chính thức

### Windows 11 Enterprise LTSC 2024 (eval)

```
https://go.microsoft.com/fwlink/?linkid=2289029&clcid=0x409&culture=en-us&country=us
```

- Bản evaluation chính thức, thời hạn dùng thử theo Microsoft.
- Không cần TPM thật; script dùng swtpm và bypass kiểm tra nếu cần.
- Phù hợp nhất khi Fido hoặc link Windows 11 Pro bị chặn.

### Windows Server 2022 (eval)

```
https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US
```

- Chọn image **Desktop Experience** (index 4).
- Bản evaluation chính thức, thời hạn dùng thử theo Microsoft.

### Windows 10 / Windows 11 Pro

Script `fetch-iso.sh` dùng dự án Fido để lấy link tải chính thức từ
Microsoft. Microsoft có thể chặn IP của Codespaces bằng Sentinel, khi đó
bạn sẽ thấy lỗi hoặc không lấy được link.

Cách xử lý:

1. Dùng `win11-ltsc` (ổn định nhất).
2. Tải ISO trên PC cá nhân từ trang Microsoft chính thức, rồi upload.
3. Truyền link trực tiếp bằng `--url`.

## 3. Tải bằng script

```bash
bash scripts/fetch-iso.sh win11-ltsc
bash scripts/fetch-iso.sh server2022
bash scripts/fetch-iso.sh win11
bash scripts/fetch-iso.sh win10
```

Kiểm tra link mà không tải:

```bash
bash scripts/fetch-iso.sh win11-ltsc --dry-run
```

Tải vào thư mục khác:

```bash
ISO_DIR=/tmp/iso bash scripts/fetch-iso.sh server2022
```

Truyền URL:

```bash
bash scripts/fetch-iso.sh win11 --url "https://example.com/Win11.iso"
```

Script kiểm tra file sau khi tải và đặt tên theo OS:

```
iso/win10.iso
iso/win11.iso
iso/win11-ltsc.iso
iso/server2022.iso
```

## 4. Tự tải trên PC rồi upload

1. Trên PC, tải ISO từ Microsoft.
2. Trong Codespaces, mở thư mục `iso/`.
3. Kéo file vào VS Code Explorer, hoặc dùng `gh codespace cp`:

```bash
gh codespace cp ./Win11.iso remote:~/winvm-codespaces-vip/iso/win11.iso
```

4. Kiểm tra:

```bash
ls -lh iso/
```

Tên file không bắt buộc tuyệt đối, nhưng nên đặt đúng để tránh nhầm:

| OS | Tên chuẩn |
| --- | --- |
| Windows 10 | `win10.iso` |
| Windows 11 | `win11.iso` |
| Windows 11 LTSC | `win11-ltsc.iso` |
| Server 2022 | `server2022.iso` |

## 5. Kiểm tra ISO

```bash
ls -lh iso/
sha256sum iso/win11.iso
```

Nếu Microsoft công bố checksum cho bản tải, so sánh với kết quả trên.
Với ISO tự tạo hoặc nguồn nội bộ, hãy chắc chắn bạn tin nguồn đó.

Kiểm tra nhanh volume label:

```bash
isoinfo -d -i iso/win11.iso | head
```

ISO Microsoft chính thức lưu payload trong **UDF**; `isoinfo -f` chỉ thấy
`README.TXT` ở lớp ISO9660. Vì vậy toolkit dùng `7z` (gói `p7zip-full`)
để kiểm tra `sources/install.wim`/`install.esd`, và fallback `isoinfo`
cho ISO tự tạo. `setup.sh` đã cài sẵn `p7zip-full`.

### Kiểm tra edition tự động

`create-vm.sh` và `run-vm.sh` kiểm tra volume label của ISO trước khi
làm bất cứ việc gì:

- `win11-ltsc`: label chứa `LTSC`, `ENTERPRISEEVAL`, hoặc bắt đầu bằng
  `CESE_` (label chính thức của bản LTSC 2024 eval).
- `server2022`: label chứa `SERVER`, hoặc bắt đầu bằng `SSS_` (label
  chính thức của bản Server 2022 eval).
- `win10` / `win11`: từ chối mọi label Server/LTSC/eval, gồm `CESE_` và `SSS_`.

Volume label thật của ISO Microsoft (đã kiểm tra ngày 2026-11-12):

| ISO | Volume label |
| --- | --- |
| Windows 11 Enterprise LTSC 2024 eval | `CESE_X64FREE_EN-US_DV9` |
| Windows Server 2022 eval | `SSS_X64FREE_EN-US_DV9` |
| Windows 10/11 Pro (consumer) | `CCCOMA_X64FRE_EN-US_DV9` |

Nếu sai edition, script dừng với thông báo tiếng Việt và không tạo disk,
không khởi động QEMU. Ví dụ:

```text
[X] ISO không phải Windows 11 Enterprise LTSC 2024 (eval)
    (volume: 'CCCOMA_X64FRE_EN-US_DV9').
    Dùng ISO LTSC eval chính thức hoặc đặt đúng file win11-ltsc.iso.
```

Chỉ dùng `VIP_SKIP_ISO_CHECK=1` khi bạn chắc chắn về ISO đặc biệt của mình:

```bash
VIP_SKIP_ISO_CHECK=1 bash scripts/create-vm.sh win11
```

## 6. Chọn edition khi cài

Autounattend chọn image theo index:

- Windows 10 Pro: index **6**
- Windows 11 Pro: index **6**
- Windows 11 Enterprise LTSC 2024: index **1**
- Windows Server 2022 Desktop Experience: index **4**

Nếu cài nhầm edition, xem log Windows Setup hoặc dùng `dism` trên ISO
để liệt kê index:

```bash
# Trên Linux: trích install.wim ra khỏi ISO trước, rồi đọc metadata.
# Cần p7zip-full và wimtools (không bắt buộc cho cài đặt).
mkdir -p /tmp/winiso
7z e -y iso/win11.iso sources/install.wim -o/tmp/winiso >/dev/null
wimlib-imagex info /tmp/winiso/install.wim
```

Trên Windows:

```powershell
dism /Get-WimInfo /WimFile:D:\sources\install.wim
```

## 7. Bản quyền và thời hạn

- Windows 10/11 Pro cần license hợp lệ nếu dùng lâu dài.
- Windows 11 Enterprise LTSC 2024 eval và Server 2022 eval có thời hạn
  dùng thử theo Microsoft; hết hạn cần license hoặc cài lại bản khác.
- Script không cung cấp key lậu, không crack, không bypass bản quyền.
- Key Pro chung trong autounattend chỉ dùng cho quá trình cài đặt
  (`VK7JG-NPHTM-C97JM-9MPGT-3V66T`), không phải key kích hoạt.

## 8. Lưu ý về dung lượng

Mỗi ISO Windows khoảng 5–7 GB. Mỗi VM qcow2 ban đầu nhỏ nhưng sẽ tăng
theo dữ liệu đã dùng. Đừng giữ quá nhiều ISO và VM trên Codespaces
4 core / 32 GB.

Kiểm tra:

```bash
df -h .
du -sh iso vm
```
