
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
- **Tự khôi phục từ không phải tiếng Việt** (bật mặc định, Cài đặt > Bộ gõ): gõ xong một từ (bấm dấu cách, dấu phẩy, Enter…) mà không phải tiếng Việt, ví dụ `restore` gõ Telex ra `rétỏe`, thì VOpenKey trả lại đúng các phím đã gõ: `restore`. Không cần bật kiểm tra chính tả.
- **Phím khôi phục từ đang gõ** (mặc định `⌥Space`, đổi được trong Cài đặt > Bộ gõ): bấm bất cứ lúc nào để trả lại các phím đã gõ cho từ đang gõ, dùng cho những từ mà tự khôi phục không bắt được (ví dụ `test` thành `tét` cũng là một từ tiếng Việt). Phần còn lại của từ đó được gõ nguyên, không chuyển đổi nữa. Khi không có gì để khôi phục, phím được chuyển cho ứng dụng như bình thường.
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
- **Thanh gợi ý khi gõ** (tắt mặc định, bật trong Cài đặt > Gợi ý): hiện các từ có thể gõ tiếp ngay dưới từ đang gõ, theo ngữ cảnh và học từ cách bạn gõ. `Tab` chọn từ đầu tiên, giữ `⌥` và bấm `1`–`5` chọn từ khác. Khi cần chuyển ô trong form lúc thanh gợi ý đang hiện, bấm `⌥Tab`: nó là `Tab` thường. Gõ liền không dấu cũng ra từ ghép, ví dụ `thietke` ra `thiết kế`. Thêm từ điển bằng cách thả file `.txt` vào thư mục từ điển, xem [engine/dictionaries](Sources/OpenKey/engine/dictionaries/README.md).
- **Snippet** (bật mặc định, Cài đặt > Snippet): bấm `⌃⌥S` (đổi được) ở bất kỳ ứng dụng nào để mở cửa sổ tìm snippet, gõ vài chữ (không dấu cũng tìm được), `↑` `↓` chọn, `↩` để chèn vào chỗ đang gõ, hoặc `⌘1`–`⌘9` để chèn nhanh. Tự tạo snippet tùy ý trong **Quản lý snippet**; có sẵn 21 prompt mẫu cho trợ lý AI (tóm tắt, dịch, viết lại, review code, viết commit message, biên bản cuộc họp…). Trong nội dung dùng được `{clipboard}` (chữ đang sao chép), `{date}` (ngày hôm nay) và `{time}` (giờ hiện tại). Snippet được dán bằng `⌘V` nên xuống dòng không bị gửi đi giữa chừng, clipboard của bạn được trả lại như cũ. Danh sách lưu ở `~/Library/Application Support/VOpenKey/Snippets/snippets.json`.
- **Trợ lý AI** (bật mặc định, Cài đặt > AI): bấm `⌃⌥A` (đổi được) ở bất kỳ ứng dụng nào để mở hộp thoại nhờ AI viết nội dung. Nếu đang chọn một đoạn văn, đoạn đó được đưa sẵn vào ô nhập (gõ yêu cầu ở dòng đầu, ví dụ "Dịch sang tiếng Anh"); `⌘↩` để tạo, kết quả hiện dần ra, `⇧⌘↩` để thay thế vùng chọn (hoặc chèn vào chỗ đang gõ), `⇧⌘C` để sao chép. Kết nối được với **OpenAI (ChatGPT)**, **Google Gemini**, **Anthropic (Claude)**, **DeepSeek**, **Qwen (Alibaba Cloud)**, **OpenRouter**, AI chạy trên máy như **Ollama** và **LM Studio**, hoặc bất kỳ máy chủ nào tương thích OpenAI (llama.cpp, vLLM…). Có nút tải danh sách model và kiểm tra kết nối.
  - **API key được bảo vệ:** chỉ lưu trong Keychain của tài khoản macOS đang dùng (không ghi ra file, không vào cài đặt, không đồng bộ iCloud), chỉ gửi trong header của yêu cầu HTTPS, không bao giờ nằm trong địa chỉ hay log, và bị che khỏi mọi thông báo lỗi. Tài khoản macOS khác trên cùng máy phải nhập key riêng. Chỉ máy trong mạng nội bộ mới được dùng `http`, và VOpenKey không theo chuyển hướng nên key không đi sang địa chỉ khác.
  - **Riêng tư:** nội dung bạn nhập và chữ đang chọn chỉ được gửi tới dịch vụ bạn chọn (hộp thoại luôn ghi rõ gửi tới đâu), không lưu lại; AI chạy trên máy thì không rời khỏi máy. Chữ đang chọn được đọc bằng Accessibility; ứng dụng nào không cho đọc thì VOpenKey bấm `⌘C` rồi trả clipboard như cũ (tắt được trong Cài đặt), và không bao giờ đọc ô mật khẩu.
  - **Cài AI chạy trên máy ngay trong VOpenKey** (Cài đặt > AI > "Cài AI chạy trên máy…"): không cần API key, không tốn tiền theo lượt, chữ của bạn không rời khỏi máy. VOpenKey **kiểm tra máy trước** (RAM, chip Apple Silicon hay Intel, ổ đĩa còn trống, phiên bản macOS, pin, nhiệt độ, bộ nhớ đang dùng), nói rõ model nào chạy thoải mái / sát giới hạn / không chạy nổi và vì sao, khuyên một model (danh sách Gemma 3 và Qwen 2.5 từ 1B đến 32B, có ghi dung lượng tải, RAM cần, chất lượng, tốc độ, tiếng Việt; hoặc tự nhập tên model của thư viện Ollama), rồi **tự cài**: tải Ollama chính thức từ GitHub, kiểm tra SHA-256, chữ ký số của hãng và công chứng của Apple, cài vào `~/Applications` (không cần quyền quản trị), khởi động máy chủ chỉ nghe trên `127.0.0.1`, tải model (bị ngắt thì tải tiếp), hỏi thử một câu và bật cho trợ lý AI. Cần macOS 14 trở lên; máy Intel chạy được nhưng chậm. Máy chủ Ollama do VOpenKey mở khi cần và tắt khi thoát VOpenKey; model rời khỏi RAM sau 10 phút không dùng. Model có chế độ "suy nghĩ" (qwen3, deepseek-r1…) vẫn dùng được: phần `<think>` bị bỏ, chỉ lấy câu trả lời. Danh sách model nằm ở `Sources/OpenKey/engine/ai/local-models.json`, tạo lại bằng `python3 scripts/update-local-models.py` (tra dung lượng thật từ thư viện Ollama).
- **Giữ bộ gõ macOS ở ABC khi gõ tiếng Việt** (bật mặc định, Cài đặt > Bộ gõ): nếu bộ gõ Vietnamese của macOS cũng đang bật thì mỗi chữ bị chuyển đổi hai lần và gõ sai, VOpenKey tự chuyển macOS về ABC.
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
