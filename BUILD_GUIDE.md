# FF AimTool — App riêng (.ipa) + Dylib cho Free Fire

## Architecture

```
┌─────────────────────┐         Darwin Notification          ┌──────────────────────┐
│   FFAimTool.app     │  ──────────────────────────────────▶ │  AimLock.dylib       │
│  (app riêng của dj) │  com.fftool.aim.head/neck/off/toggle │  (inject trong FF)   │
│                     │                                       │                      │
│  • Toggle Aim Đầu   │  ◀──────────────────────────────────  │  • Hook UpdateAiming │
│  • Toggle Aim Cổ    │  com.fftool.aim.pong (response)       │  • Snap to head/neck │
│  • FOV slider       │                                       │  • HUD trong FF      │
│  • Status display   │         App Group UserDefaults        │                      │
│                     │  ──────────────────────────────────▶  │  • Đọc config 1s/lần│
└─────────────────────┘  group.com.fftool.aim                 └──────────────────────┘
```

## File structure

```
ff-aimtool/
├── main.m              — app entry point
├── AppDelegate.h/.m    — app delegate
├── ViewController.m    — UI control panel
├── AimEngine.h/.m      — control logic, Darwin notify, App Group sync
├── AimLock_v2.mm       — dylib inject vào FF (thay AimLock.mm cũ)
└── BUILD_GUIDE.md      — file này
```

## Cách 1: Build bằng GitHub Actions (không cần Mac)

Tạo repo GitHub private → upload toàn bộ folder → tạo file:
`.github/workflows/build.yml`

```yaml
name: Build FFAimTool IPA

on: [push, workflow_dispatch]

jobs:
  build:
    runs-on: macos-14
    steps:
    - uses: actions/checkout@v4

    - name: Build FFAimTool.ipa
      run: |
        # Tạo Xcode project
        cat > FFAimTool.xcodeproj/project.pbxproj << 'PBXEOF'
        # (xem phần dưới)
        PBXEOF

        xcodebuild -scheme FFAimTool \
          -sdk iphoneos \
          -configuration Release \
          CODE_SIGNING_REQUIRED=NO \
          CODE_SIGNING_ALLOWED=NO \
          -derivedDataPath build/

        # Đóng gói IPA
        mkdir -p Payload
        cp -r build/Build/Products/Release-iphoneos/FFAimTool.app Payload/
        zip -r FFAimTool.ipa Payload/

    - uses: actions/upload-artifact@v4
      with:
        name: FFAimTool
        path: FFAimTool.ipa
```

## Cách 2: Dùng theos (trên Mac hoặc Linux)

```makefile
# Theos Makefile
ARCHS = arm64
TARGET = iphone:clang:16.5:13.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = FFAimTool

FFAimTool_FILES = main.m AppDelegate.m ViewController.m AimEngine.m
FFAimTool_FRAMEWORKS = UIKit Foundation CoreMotion
FFAimTool_PRIVATE_FRAMEWORKS = notify
FFAimTool_BUNDLE_ID = com.fftool.aim

include $(THEOS_MAKE_PATH)/application.mk
```

## Entitlements cần thiết

File `FFAimTool.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
    <!-- App Group: chia sẻ UserDefaults với FF dylib -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.fftool.aim</string>
    </array>
    <!-- Background processing để giữ kết nối -->
    <key>UIBackgroundModes</key>
    <array>
        <string>processing</string>
    </array>
</dict>
</plist>
```

## Quy trình hoàn chỉnh

### Bước 1: Cài FFAimTool.ipa
```
ESign → Import FFAimTool.ipa → Sign → Install
```

### Bước 2: Inject AimLock_v2 vào FF (thay AimLock.mm cũ)
```sh
# Trong iSH (khi có python3 + inject_ipa.py)
python3 inject_ipa.py FreeFire.ipa AimLock.dylib
```
→ FreeFire_Modded.ipa → ESign → Install

### Bước 3: Sử dụng
1. Mở Free Fire trước (để dylib load)
2. Mở FFAimTool app
3. Nhấn "Kết nối Free Fire" → thấy ✅ là ok
4. Chọn **Aim Đầu** hoặc **Aim Cổ**
5. Bật switch Aimlock → xanh = đang hoạt động
6. Vào game — aim tự động

### Trong game
- HUD góc trên trái FF hiện: `🎯 ĐẦU` hoặc `🎯 CỔ` hoặc `⬜ OFF`
- Thay đổi chế độ: chuyển sang FFAimTool → đổi → quay lại FF

## Darwin Notification (không cần entitlement đặc biệt)

`notify_post()` / `notify_register_dispatch()` là cross-process API của Apple,
hoạt động trên non-jailbroken iOS mà không cần entitlement.
Đây là cách hợp lệ để 2 app giao tiếp nếu cùng biết notification key.

## Lưu ý bảo mật

- App Group UserDefaults hoạt động khi cả 2 app cùng Team ID
- Nếu dùng free cert (7 ngày): resign mỗi tuần
- Darwin notify hoạt động bất kể Team ID → luôn dùng được
