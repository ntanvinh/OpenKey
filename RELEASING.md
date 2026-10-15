# Phát hành VOpenKey AI

Mỗi phiên bản là **một GitHub Release** (tag `v<phiên bản>`, ví dụ `v3.0.0`) chứa file của từng nền tảng:

| Nền tảng | File | Ai tạo | Ở đâu |
|---|---|---|---|
| macOS | `VOpenKey-<phiên bản>.dmg` + `.sha256` | `scripts/release.sh` | Máy Mac này |
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
4. **Commit `release: VOpenKey AI x.y.z`, push `master`, tạo GitHub Release `vx.y.z`** kèm `.dmg` và `.sha256`; mô tả phát hành lấy từ mục CHANGELOG.
5. **Windows tự chạy**: Release vừa publish kích hoạt workflow `Release Windows`; script chờ nó xong và kiểm tra `VOpenKey-x.y.z-Windows.zip` đã nằm trong Release. Dùng `--no-windows` để bỏ qua.
6. **Cuối cùng mới ghi `version.json`** rồi commit và push. Các app đọc file này trên nhánh `master` để báo có bản mới, nên chỉ khi mọi file tải về đã sẵn sàng người dùng mới nhận thông báo.

Nếu bước Windows lỗi, script dừng sau khi đã có Release macOS nhưng **chưa** ghi `version.json` (chưa ai bị báo cập nhật). Sửa lỗi, chạy lại workflow bằng `gh workflow run release-windows.yml -f tag=vx.y.z`, rồi `scripts/release.sh --announce` để làm nốt bước 6.

Cần chuẩn bị một lần: chứng chỉ Developer ID trong keychain (đã có), hồ sơ notarize (`xcrun notarytool store-credentials VOpenKey-notary ...`, xem đầu `scripts/release.sh`), và `gh auth login`. Trên GitHub không cần cài đặt thêm: workflow tự khai báo quyền `contents: write`.

`scripts/version.sh` dùng riêng được: `scripts/version.sh` (xem phiên bản ở từng file và có khớp không), `next patch`, `bump patch`, `announce`.

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
