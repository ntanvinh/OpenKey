## Cách build VOpenKey cho macOS

Yêu cầu:
- macOS 13 (Ventura) trở lên, Xcode 15 trở lên (đã thử với Xcode 26).
- Để ký và phát hành: chứng chỉ **Developer ID Application** trong Keychain (lệnh dưới tự tìm).

Dự án nằm ở `Sources/OpenKey/macOS/OpenKey.xcodeproj` (target và scheme `OpenKey`, sản phẩm ra là `VOpenKey.app`).

### Chạy thử khi phát triển

```
scripts/dev.sh
```

Mỗi lần chạy, script tự tăng patch version (ví dụ `3.0.0` thành `3.0.1`) bằng `scripts/version.sh bump patch`, rồi build bản Debug, ký, cài vào `~/Applications/VOpenKey.app` và mở. Phiên bản được đồng bộ trong cấu hình macOS, Windows và changelog; `version.json` không đổi nên bản dev không được công bố là bản cập nhật. Thêm `--reset-permissions` để xóa quyền đã cấp và xem lại cửa sổ cấp quyền lần đầu, `--no-open` để chỉ cài.

Nên chạy bằng lệnh này thay vì bấm Run trong Xcode hoặc mở thẳng từ thư mục build: macOS chỉ liệt kê app trong *Cài đặt hệ thống -> Quyền riêng tư & Bảo mật* khi tìm thấy nó, mà thư mục build nằm ẩn (`~/Library/Developer/Xcode/DerivedData`) nên app không hiện trong danh sách, nút "+" cũng khó chọn tới. Ký bằng cùng một chứng chỉ mỗi lần còn giúp các quyền đã cấp được giữ qua các lần build.

Khi cần quyền ở chế độ dev mà không thấy app trong danh sách, cửa sổ cấp quyền có biểu tượng để kéo thả vào danh sách và nút **Hiện trong Finder**.

### Phát hành

```
scripts/release.sh                 # build, ký, ra dist/VOpenKey-<phiên bản>.dmg
scripts/release.sh --notarize      # thêm: Apple xác nhận (notarize) và gắn ticket vào app và dmg
scripts/release.sh --publish       # thêm: tạo GitHub Release (cần --notarize, vì đây là đưa lên mạng)
```

`scripts/release.sh --help` in lại hướng dẫn này. Kết quả nằm trong `dist/`: file `.dmg` (bản universal Apple Silicon + Intel, hardened runtime) và file `.sha256`.

Không có `--notarize`, bản dmg vẫn chạy trên máy build nhưng máy khác sẽ cảnh báo không kiểm tra được phần mềm. Một lần duy nhất, lưu thông tin để notarize vào Keychain:

```
xcrun notarytool store-credentials VOpenKey-notary --apple-id <Apple ID> --team-id <Team ID> --password <app-specific password>
```

(app-specific password tạo ở appleid.apple.com, mục Đăng nhập và Bảo mật). Dùng tên profile khác thì đặt `NOTARY_PROFILE=<tên>`. Dùng chứng chỉ khác thì đặt `SIGN_IDENTITY="Developer ID Application: ..."`.

### Tăng phiên bản

Sửa `MARKETING_VERSION` và `CURRENT_PROJECT_VERSION` trong project (Xcode: target OpenKey, tab General, Version và Build) và `version.json` ở thư mục gốc. Tính năng "Kiểm tra bản mới" của app đọc `version.json` từ nhánh `master` rồi so số build, nên phải đẩy file này lên cùng lúc phát hành.

### Đổi tên, repo, bundle ID

Tên app, bundle ID và các đường dẫn nằm ở một chỗ: `Sources/OpenKey/macOS/ModernKey/AppInfo.h`. Bundle ID cũng nằm ở `PRODUCT_BUNDLE_IDENTIFIER` trong project và ở `scripts/common.sh`. Đổi bundle ID nghĩa là macOS coi là app khác: quyền phải cấp lại và cài đặt bắt đầu từ đầu.
