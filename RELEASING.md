# Phát hành VOpenKey AI

Mỗi phiên bản là **một GitHub Release** (tag `v<phiên bản>`, ví dụ `v3.0.0`) chứa file của từng nền tảng:

| Nền tảng | File | Ai tạo | Ở đâu |
|---|---|---|---|
| macOS | `VOpenKey-<phiên bản>.dmg` + `.sha256`, và `VOpenKey.dmg` (cùng file, không có số phiên bản) | `scripts/release.sh` | Máy Mac này |
| Windows | `VOpenKey-<phiên bản>-Windows.zip` + `.sha256` | `.github/workflows/release-windows.yml` | GitHub Actions (`windows-latest`) |
| Linux | chưa có, xem cuối file | | |

## Phát hành bằng một lệnh

```
scripts/release.sh patch          # 3.0.0 -> 3.0.1   (cũng có: minor, major, hoặc số cụ thể như 3.1.0)
scripts/release.sh current        # phát hành đúng phiên bản đang có trong project, không nâng
```

Thêm `--dry-run` để chỉ kiểm tra và xem kế hoạch, `--yes` để không hỏi xác nhận. Lệnh làm lần lượt:

1. **Kiểm tra trước khi đụng vào file nào**: đang ở nhánh `master`, đã đồng bộ với `origin`, cây làm việc sạch (script tự commit, nên hãy commit việc dở trước), `gh` đã đăng nhập, hồ sơ notarize có trong keychain, workflow Windows đã được commit, tag chưa tồn tại.
2. **Nâng phiên bản** bằng `scripts/version.sh bump`: `project.pbxproj` (MARKETING_VERSION, CURRENT_PROJECT_VERSION tăng 1), `OpenKey.rc` của Windows, và thêm mục vào `CHANGELOG.md` (nếu bạn đã tự viết sẵn mục cho phiên bản đó thì giữ nguyên).
3. **Build, ký và notarize** `VOpenKey AI.app` và file `.dmg`. Nếu bước này lỗi, phiên bản vừa nâng được hoàn tác.
4. **Commit `release: VOpenKey AI x.y.z`, push `master`, tạo GitHub Release `vx.y.z`** kèm `VOpenKey-x.y.z.dmg`, `.sha256` và `VOpenKey.dmg` (bản sao tên cố định, xem "Tự cập nhật và link cố định" bên dưới); mô tả phát hành lấy từ mục CHANGELOG. **Từ lúc này các app Mac đã có tính năng tự cập nhật bắt đầu thấy bản mới** (chúng hỏi GitHub, không đọc `version.json`).
5. **Windows tự chạy**: Release vừa publish kích hoạt workflow `Release Windows`; script chờ nó xong và kiểm tra `VOpenKey-x.y.z-Windows.zip` đã nằm trong Release. Dùng `--no-windows` để bỏ qua.
6. **Cuối cùng mới ghi `version.json`** rồi commit và push. App Windows và các app Mac đời cũ (chưa tự cập nhật) đọc file này trên nhánh `master` để báo có bản mới, nên chỉ khi mọi file tải về đã sẵn sàng họ mới nhận thông báo.

Nếu bước Windows lỗi, script dừng sau khi đã có Release macOS nhưng **chưa** ghi `version.json` (app Windows và các Mac đời cũ chưa bị báo cập nhật; app Mac mới thì đã tự cập nhật được từ Release). Sửa lỗi, chạy lại workflow bằng `gh workflow run release-windows.yml -f tag=vx.y.z`, rồi `scripts/release.sh --announce` để làm nốt bước 6.

Cần chuẩn bị một lần: chứng chỉ Developer ID trong keychain (đã có), hồ sơ notarize (`xcrun notarytool store-credentials VOpenKey-notary ...`, xem đầu `scripts/release.sh`), và `gh auth login`. Trên GitHub không cần cài đặt thêm: workflow tự khai báo quyền `contents: write`.

`scripts/version.sh` dùng riêng được: `scripts/version.sh` (xem phiên bản ở từng file và có khớp không), `next patch`, `bump patch`, `announce`.

## Tự cập nhật và link cố định (macOS)

**Link cho website và người dùng mới**: GitHub đổi `releases/latest/download/<tên file>` thành file đó của Release mới nhất, nên link không phải sửa mỗi lần phát hành, miễn là tên file không đổi:

- Tải ngay: `https://github.com/ntanvinh/OpenKey/releases/latest/download/VOpenKey.dmg`
- Trang của bản mới nhất: `https://github.com/ntanvinh/OpenKey/releases/latest`

Vì vậy mỗi Release phải có **`VOpenKey.dmg`** (script làm sẵn, cùng file với `VOpenKey-x.y.z.dmg`). Trong `docs/vopenkey-ai/product.json` (và bản sao `marketing/website/product.json`), `links.macos` đang trỏ vào link thứ nhất; sửa xong chạy `v-publish-app-info` một lần, sau đó không phải đụng tới website khi có bản mới.

**App tự cập nhật** (`AppUpdater.m`, giao diện ở `OpenKeyManager.m`): khi khởi động rồi cứ 6 giờ, app gọi `https://api.github.com/repos/ntanvinh/OpenKey/releases/latest` (nếu GitHub từ chối vì hỏi quá nhiều thì xem trang `releases/latest` để biết tag). Bản mới hơn thì tải `VOpenKey-x.y.z.dmg`, rồi chỉ cài khi **tất cả** đều đúng: đúng dung lượng và SHA-256 mà Release công bố (`digest` của API, nếu không có thì file `.sha256`), mở được, bên trong có đúng một `.app` thật (không phải link), tên định danh `vn.io.lssoft.vopenkey`, phiên bản trong app khớp tag, và **chữ ký là Developer ID của Team `39SH232CQ4`** (`VOK_TEAM_ID` trong `AppInfo.h`). Bản đã tải nằm ở `~/Library/Application Support/VOpenKey/Updates/ready`; khi người dùng khởi động lại, một trình giúp việc nhỏ (`/bin/sh`, chạy sau khi app thoát) chép bản mới cạnh app cũ, đổi chỗ, mở lại, và nếu có bước nào hỏng thì để nguyên app cũ và mở lại nó.

Những điều người phát hành phải giữ cho tính năng này chạy:

- Tag là `v<x.y.z>` và `CFBundleShortVersionString` của app trong dmg là đúng `x.y.z` (`scripts/release.sh` bảo đảm cả hai từ cùng một số trong project). Release **không** để là draft hay pre-release, vì `releases/latest` bỏ qua chúng.
- File tải về tên `VOpenKey-x.y.z.dmg`, app nằm ở gốc dmg (một `.app` duy nhất; link `Applications` thì được).
- **Ký bằng cùng Developer ID Team.** Nếu một ngày đổi chứng chỉ sang Team khác, các app đang cài sẽ từ chối bản mới (và nói rõ lý do): lúc đó phải đổi `VOK_TEAM_ID`, phát hành, và nhắc người dùng tải bản đó bằng tay một lần.
- Bộ cập nhật không đòi bản notarize (file mà chính app tải về không bị gắn nhãn quarantine nên Gatekeeper không xét lại nó; chữ ký Team đã ghim là bảo đảm chính), nhưng điều đó chưa được thử trên máy thật với bản chưa notarize. Cứ notarize như mọi lần: người tải bằng tay vẫn cần.

Chạy bộ test (không dùng mạng, không cài gì ngoài thư mục tạm): `Sources/OpenKey/macOS/tests/run-app-update-test.sh`. Thêm `VOK_TEST_REAL_DMG=1` để thử cả bước mở file `.dmg` thật bằng `hdiutil` (mặc định bước này được bỏ qua và test nói SKIPPED).

## Build Windows thử trên máy Mac này

Không build trực tiếp được: dự án là Visual Studio (`v143`, Win32 API, file `.rc`). Có ba cách:

- **GitHub Actions** (đã cấu hình, không cần máy Windows): workflow `MSBuild` tự build mỗi lần push lên `master` và đính kết quả vào lần chạy (artifact `OpenKey`). Chạy thử một nhánh bằng `gh workflow run msbuild.yml --ref <nhánh>`.
- **Máy Windows thật** (qua RDP hoặc SSH): cài Visual Studio 2022 Build Tools (thành phần "Desktop development with C++"), rồi `msbuild Sources\OpenKey\win32\OpenKey -p:Configuration=Release -p:Platform=x64` (và `x86`). File ra ở `Release\` và `x64\Release\`.
- **Máy ảo Windows trên Mac** (Parallels/UTM, Windows 11 ARM): cùng cách với máy Windows thật; Visual Studio trên ARM vẫn build được x86/x64.

Mỗi lần chạy thử trên Windows nên kiểm tra tay: gõ Telex, VNI, đổi chế độ bằng phím tắt, bảng gõ tắt, kiểm tra bản mới. Trình cập nhật chỉ thay `OpenKey64.exe`.

## Ký số (chưa có)

File `.exe` chưa được ký, Windows SmartScreen có thể cảnh báo khi tải về. Muốn ký cần chứng chỉ code signing (OV hoặc EV) hoặc dịch vụ Azure Trusted Signing, thêm một bước `signtool` vào workflow trước khi nén zip.

## Linux

Thư mục `Sources/OpenKey/linux` hiện chỉ có README ("Coming soon"), chưa có mã nguồn. Phần lõi gõ (`Sources/OpenKey/engine`) dùng chung được, còn phần giao diện/nhận phím cho Linux cần viết mới.
