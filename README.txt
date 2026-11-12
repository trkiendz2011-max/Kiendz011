WINVM CODESPACES VIP - HUONG DAN NHANH
=======================================

Tai khoan mac dinh
------------------
User     : VIP
Password : Vip@2026
Quyen    : Administrator

Doi mat khau ngay trong PowerShell:
  net user VIP "MatKhauMoiCuaBan"

Sau khi Windows khoi dong lan dau
---------------------------------
Script C:\Windows\Setup\Scripts\setup-win.ps1 tu chay va:
  - Cai tieng Viet (vi-VN), ban phim Telex, mui gio Viet Nam.
  - Cai Mesa GPU phan mem (OpenGL + Vulkan lavapipe + anti-lag).
  - Cai Vulkan runtime cua LunarG.
  - Cai DXVK vao C:\VIP\DXVK.
  - Toi uu chong lag (co backup de hoan tac).
  - Bat fast startup, boot menu VIP, wallpaper VIP.

Log: C:\VIP\setup.log
Menu: C:\VIP\scripts\vip-tools.ps1 (shortcut "VIP Tools" tren desktop)

Chay lai tung phan
------------------
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-vi.ps1
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-mesa.ps1
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-vulkan.ps1
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-dxvk.ps1
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\optimize.ps1
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\restore-defaults.ps1

Deploy DXVK vao mot game
------------------------
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-dxvk.ps1 -GameDir "C:\Games\TenGame"

DXVK se copy d3d8.dll, d3d9.dll, d3d10core.dll, d3d11.dll, dxgi.dll vao thu muc game.
Ban sao DLL goc nam trong C:\VIP\backup\dxvk\<ten-game>.

Hoan tac
--------
  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\restore-defaults.ps1
  Khoi dong lai Windows sau khi khoi phuc.

Luu y hieu nang
---------------
GitHub Codespaces khong co KVM nen QEMU phai gia lap CPU bang TCG.
Windows se cham hon may that rat nhieu. Mesa, Vulkan va DXVK deu chay
bang CPU (phan mem), khong phai GPU that. Chi nen dung de hoc/dev.
