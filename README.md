
# VOpenKey
### [Tải bản mới nhất](https://github.com/ntanvinh/OpenKey/releases/latest)

### Bộ gõ tiếng Việt nguồn mở cho macOS, phát triển bởi LSSoft, fork từ [OpenKey](https://github.com/tuyenvm/OpenKey) của Mai Vũ Tuyên.
Bộ gõ tiếng Việt cho macOS, sử dụng kỹ thuật `Backspace`. Loại bỏ lỗi gạch chân khó chịu ở bộ gõ mặc định. Hoàn toàn miễn phí và là nguồn mở.

### Mã nguồn được mở công khai, minh bạch dưới giấy phép GPL-3.0. Điều này nghĩa là bạn hoàn toàn có thể tải mã nguồn về tự build, cải tiến theo mục đích của bạn. Nếu bạn tái phân phối bản cải tiến của bạn, thì nó cũng phải là mã nguồn mở và thông báo bản gốc là OpenKey của Mai Vũ Tuyên.

### Lưu ý, khi sử dụng VOpenKey, bạn nên thoát hẳn OpenKey gốc và các bộ gõ khác vì 2 chương trình bộ gõ sẽ xung đột nhau, dẫn đến thao tác không chính xác. Khi mở lần đầu, VOpenKey sẽ tự nhập cài đặt từ OpenKey gốc (nếu có) và hỏi có muốn thoát OpenKey gốc không.

*Ảnh minh họa dưới đây lấy từ OpenKey gốc, giao diện của VOpenKey đã được làm lại theo phong cách macOS.*

![Giao diện](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/openkey-main-control.png "Main UI")
![Giao diện](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/openkey-main-control-2.png "Main UI")
![Giao diện](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/openkey-main-control-3.png "Main UI")
![Menu](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/openkey-small-control.png "Menu bar")
![Gõ tắt](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/openkey-macro.png "Macro")
![Chuyển mã](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/openkey-convert-tool.png "ConvertTool")

## Hỗ trợ kiểu gõ
- Telex
- VNI
- Simple Telex

## Bảng mã thông dụng:
- Unicode (Unicode dựng sẵn).
- TCVN3 (ABC).
- VNI Windows.
- Unicode Compound (Unicode tổ hợp).
- Vietnamese Locale CP 1258.
- ...

## Tính năng:
- **Modern orthography** (On/Off) - Đặt dấu oà, uý thay vì òa, úy.
- **Quick Telex** (On/Off) - Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- **Grammar check** (On/Off) - Kiểm tra ngữ pháp.
- **Spelling check** (On/Off) - Kiểm tra chính tả.
- **Restore key if invalid word** (on/off) - Phục hồi phím với từ sai.
- **Run on startup** (On/Off) - Chạy cùng macOS.
- **Gray menu bar icon** (On/Off) - Biểu tượng xám trên thanh menu phù hợp với chế độ Dark mode.
- **Switch input mode by shortcut key** - Đổi chế độ gõ bằng phím tắt tùy chọn.
- **Autocorrect fixed** (On/Off) - Sửa lỗi autocorrect trên trình duyệt như Chrome, Safari, Firefox, Microsoft Excel.
- **Underline issue fixed on macOS** (On/Off) - Sửa lỗi gạch chân trên macOS.
- **Tạm tắt kiểm tra chính tả bằng phím Ctrl** (On/Off) (Bản 1.5 về sau).
- **Tạm tắt OpenKey bằng phím Cmd/Alt** (On/Off) (Bản 2.0.1 về sau).
- **Cho phép dùng f z w j làm phụ âm đầu** (On/Off) (Bản 1.5 về sau).
- **Gõ tắt phụ âm đầu: f->ph, j->gi, w->qu** (On/Off) (Bản 1.6 về sau).
- **Gõ tắt phụ âm cuối: g->ng, h->nh, k->ch** (On/Off) (Bản 1.6 về sau).
- **Hiện biểu tượng trên thanh Dock** (On/Off) (Bản 2.0.1 về sau). Bấm vào icon trên thanh Dock sẽ mở nhanh Bảng điều khiển.
- **Macro** - Tính năng gõ tắt vô cùng tiện lợi. Gõ tắt của macOS chỉ hỗ trợ 20 ký tự, còn OpenKey không giới hạn ký tự.
- **Chuyển chế độ thông minh:** (On/Off) (Bản 1.2 về sau) - Bạn đang dùng chế độ gõ Tiếng Việt trên ứng dụng A, bạn chuyển qua ứng dụng B trước đó bạn dùng chế độ gõ Tiếng Anh, OpenKey sẽ tự động chuyển qua chế độ gõ Tiếng Anh cho bạn, khi bạn quay lại ứng dụng A, OpenKey tất nhiên sẽ chuyển lại chế độ gõ tiếng Việt, rất cơ động.
- **Viết Hoa chữ cái đầu câu** (On/Off) (Bản 1.2 về sau) - Khi gõ văn bản dài, đôi khi bạn quên ghi hoa chữ cái đầu câu khi kết thúc một câu hoặc khi xuống hàng, tính năng này sẽ tự ghi hoa chữ cái đầu câu cho bạn, thật tuyệt vời.
- **Chế độ “Gửi từng phím”:** (On/Off) (Bản 1.1 về sau) mặc định dùng kỹ thuật mới gửi dữ liệu 1 lần thay vì gửi nhiều lần cho chuỗi ký tự, nên nếu có ứng dụng nào không tương thích, hãy bật tính năng này lên, mặc định thì nên tắt vì kỹ thuật mới sẽ chạy nhanh hơn.
- **Cập nhật tự động:** (Bản 1.3 về sau) tính năng hỗ trợ cập nhật phiên bản OpenKey mới nhất mỗi khi mở OpenKey hoặc tự check trong phần mục Giới thiệu.
- **Công cụ chuyển mã:** (Bản 1.4 về sau) hỗ trợ chuyển mã qua lại văn bản, thích hợp cho việc chuyển đổi văn bản cũ viết bằng VNI, TCVN3 qua Unicode,... Hỗ trợ cấu hình phím tắt chuyển mã nhanh, bảng cấu hình tùy chọn chuyển mã.
- **Tự ghi nhớ bảng mã theo ứng dụng:** (Bản 2.0.1 về sau) Phù hợp cho các bạn dùng Photoshop, CAD,... với các bảng mã VNI, TCVN3. OpenKey tự ghi nhớ ứng dụng nào dùng bảng mã nào để lần sau sử dụng Photoshop, CAD,... OpenKey có thể tự chuyển sang bảng mã đó.
- ...


[Changelog](CHANGELOG.md)

## Cài đặt:
Yêu cầu macOS 13 (Ventura) trở lên.

Tải file `VOpenKey-<phiên bản>.dmg` từ [trang Releases](https://github.com/ntanvinh/OpenKey/releases/latest), mở ra rồi kéo `VOpenKey.app` vào thư mục `Applications`. Mở VOpenKey từ đó.

## Cấp quyền khi mở lần đầu:
VOpenKey cần 2 quyền của macOS để đọc phím bạn gõ và thay bằng chữ có dấu. Khi mở lần đầu sẽ có cửa sổ **Chào mừng đến với VOpenKey**, bạn chỉ cần:
1. Bấm công tắc **Trợ năng (Accessibility)**, rồi bật **VOpenKey** trong Cài đặt hệ thống.
2. Bấm công tắc **Giám sát đầu vào (Input Monitoring)**, rồi bật **VOpenKey** tiếp.

Cửa sổ tự cập nhật theo từng công tắc và tự khởi động bộ gõ khi đủ quyền, không cần mở lại app. Nếu macOS yêu cầu thoát và mở lại, cửa sổ sẽ có nút **Khởi động lại**. Xem lại hay mở các quyền này bất cứ lúc nào ở *Cài đặt -> Hệ thống -> Quyền*. **Không tắt các quyền này khi đang dùng VOpenKey.**

Nếu VOpenKey không có trong danh sách của Cài đặt hệ thống (thường do app chạy từ thư mục build chứ không phải `Applications`), cửa sổ sẽ có biểu tượng để kéo thả vào danh sách và nút **Hiện trong Finder**.

### Secure Input (ô mật khẩu, Secure Keyboard Entry...)
Khi một ứng dụng bật *Secure Input* (ô nhập mật khẩu, Terminal/iTerm2 bật *Secure Keyboard Entry*, hoặc ứng dụng lỗi quên tắt), macOS giấu mọi phím khỏi các ứng dụng khác nên OpenKey không đọc được phím để chuyển dấu. Đây là giới hạn của macOS, không phải lỗi riêng của VOpenKey. VOpenKey xử lý như sau, rồi tự trả lại khi Secure Input hết:
- **App đang gõ chính là app giữ Secure Input** (ô mật khẩu, Terminal bật Secure Keyboard Entry, màn hình khóa, hộp thoại mật khẩu của hệ thống): biểu tượng VOpenKey chuyển sang **E** (tiếng Anh). VOpenKey không tự dùng bộ gõ macOS ở đây vì bộ gõ đó cũng sẽ biến đổi cả mật khẩu bạn gõ.
- **App đang gõ là app bình thường, còn Secure Input do một app khác đang chạy nền giữ** (thường là app quên tắt): VOpenKey tự chuyển sang bộ gõ **Vietnamese của macOS** (cùng kiểu gõ Telex/VNI) để bạn vẫn gõ được tiếng Việt, và chuyển lại khi hết. Cần bật sẵn bộ gõ này tại *System Settings -> Keyboard -> Input Sources -> Vietnamese*. Bộ gõ của macOS có gạch chân, VOpenKey không tắt được. Tắt tính năng tự chuyển này bằng `defaults write vn.io.lssoft.vopenkey vSecureInputFallback -int 0`.

Khi Secure Input đang bật, menu của VOpenKey có một dòng cho biết app nào đang giữ; rê chuột lên biểu tượng để xem VOpenKey đang làm gì. Cài đặt ngôn ngữ đã lưu không bị đổi.

## Build và phát hành:
Xem [macOS_Build.md](macOS_Build.md). Tóm tắt:
- `scripts/dev.sh`: build bản dev, ký, cài vào `~/Applications` và mở.
- `scripts/release.sh`: build bản phát hành, ký Developer ID, đóng gói `dist/VOpenKey-<phiên bản>.dmg`. Thêm `--notarize` để Apple xác nhận, `--publish` để đăng lên GitHub Releases.

## Tác giả
- **LSSoft** - phát triển VOpenKey (bản fork này): [github.com/ntanvinh/OpenKey](https://github.com/ntanvinh/OpenKey).
- **Mai Vũ Tuyên** - tác giả OpenKey gốc: [github.com/tuyenvm/OpenKey](https://github.com/tuyenvm/OpenKey), maivutuyen.91@gmail.com, fanpage [OpenKeyVN](https://www.facebook.com/OpenKeyVN).

## Liên kết
- [OpenKey cho Windows, xem chi tiết tại đây](https://github.com/tuyenvm/OpenKey/tree/master/Sources/OpenKey/win32)
- [OpenKey cho Linux (đang phát triển)](https://github.com/tuyenvm/OpenKey/tree/master/Sources/OpenKey/linux)
## Một điều nhỏ nhoi
Đừng quên ủng hộ tác giả gốc của OpenKey bằng cách mua ly cafe cho tác giả tỉnh ngủ nhé:  
[Buy me a coffee ^^](https://tuyenvm.github.io/donate.html)  
[Redbull cũng được ^^](https://paypal.me/tuyenmai)  
Hoặc trực tiếp qua ví momo:   
![Donate by momo](https://tuyenvm.github.io/images/momo.png "Momo").   

Cảm ơn các bạn rất nhiều.
