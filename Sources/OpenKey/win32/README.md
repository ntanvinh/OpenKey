# VOpenKey AI for Windows
[![GitHub release](https://img.shields.io/github/v/release/ntanvinh/OpenKey.svg)](https://github.com/ntanvinh/OpenKey/releases/latest)
- VOpenKey AI phiên bản cho Windows bắt đầu từ bản 1.5, có tất cả các tính năng của bản macOS.  
- VOpenKey AI mặc định chạy ở chế độ `Administrator` để có thể dễ dàng gõ Tiếng Việt trong **game**. Mã nguồn đã được phát hành công khai dưới giấy phép **GPL** nên các bạn hoàn toàn yên tâm về tính minh bạch của chương trình, không keylog, không backdoor,...
- VOpenKey AI for Windows hỗ trợ từ Windows Vista trở lên, Windows XP thì chưa có cơ hội để test, Windows 2000 trở về trước thì chắc chắn không thể hỗ trợ rồi.
![Giao diện chính](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/win32_2.0_1.png "Main UI")



## Tính năng
Mặc định, VOpenKey AI cho phép gõ với chế độ bỏ dấu tự do, không cần phải bỏ dấu sau nguyên âm.
* Hỗ trợ kiểu gõ:
	* Telex
	* VNI
	* Simple Telex
	* Có thể yêu cầu thêm kiểu gõ.
* Hỗ trợ bảng mã:
	* Unicode dựng sẵn
	* TCVN3 (ABC)
	* VNI Windows
	* Unicode Tổ hợp
	* Vietnamese locale CP 1258
* Chính tả:
	* Bật tắt kiểm tra chính tả
	* Tự khôi phục phím với từ sai
	* Cho phép chữ "z w j f" làm phụ âm đầu
	* Tạm tắt chính tả bằng phím Ctrl
	* Tạm tắt VOpenKey AI bằng phím Alt
* Tùy chọn:
	* Tự cấu hình phím tắt chuyển Anh - Việt
	* Bỏ dấu kiểu mới (oà, uý) và kiểu cũ (òa úy)
	* Sửa lỗi gợi ý trên thanh địa chỉ trình duyệt, Excel
	* Hiện bảng điều khiển khi khởi động
	* Hai loại biểu tượng trên system tray (đồng bộ với Win10)
	* Khởi động cùng Windows.
	* Chạy với chế độ Admin.
	* Sửa lỗi trên các trình duyệt Chromium
	* Hỗ trợ các ứng dụng metro trên Windows 10
* Công cụ và tính năng nâng cao:
	* Loại trừ ứng dụng thông minh
	* Tự ghi nhớ bảng mã theo ứng dụng
	* Viết Hoa chữ cái đầu câu
	* Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)
	* Gõ tắt và công cụ soạn gõ tắt.
	* Chuyển mã với nhiều tùy chọn.
	* Gõ tắt phụ âm đầu: f->ph, j->gi, w->qu
	* Gõ tắt phụ âm cuối: g->ng, h->nh, k->ch

## Tính năng của VOpenKey AI trên Windows
Ngoài bộ gõ, bản Windows (x86 và x64) có các tính năng giống bản macOS. Mở **Gợi ý, snippet và công cụ...** từ menu của biểu tượng khay để bật và đổi phím tắt.

| Tính năng | Cách dùng | Phím tắt mặc định |
|---|---|---|
| Thanh gợi ý từ | Hiện dưới con trỏ khi gõ: `Tab` chọn gợi ý đầu, `Alt+1` đến `Alt+5` chọn gợi ý khác, `Esc` tắt thanh. Vừa chọn gợi ý xong mà gõ dấu câu (`. , ; : ! ? ) ] } >`) thì dấu câu thế chỗ dấu cách thừa, gõ chữ ngay sau dấu câu thì tự có dấu cách. Không hiện trong terminal (danh sách chương trình tự tắt sửa được) và ô mật khẩu. Độ trong suốt thường và khi con trỏ nằm trên thanh chỉnh được. Chỉ dùng với bảng mã Unicode. Mặc định tắt. Chỉnh ở **Trong suốt và chương trình tự tắt...** trong "Gợi ý, snippet và công cụ..." | |
| Gõ tắt chờ xác nhận | Gõ `vn` ở cuối `example.com.vn` không bị đổi; gõ tắt hiện trên thanh gợi ý, `Tab` để thay | |
| Snippet | Bảng tìm nhanh các đoạn chữ có sẵn (21 prompt cho AI) và của bạn, dán vào chỗ đang gõ; có `{clipboard}`, `{date}`, `{time}` | `Ctrl+Alt+S` |
| Đổi chữ hoa thường | Chọn chữ rồi nhấn phím tắt: CHỮ HOA, chữ thường, Viết Hoa Từng Từ, camelCase, snake_case, bỏ dấu... kèm xem trước. `Alt+1`...`Alt+9`, `Alt+0` hoặc ↑ ↓ Enter để chọn. **Tự hiện khi bôi đen** (kéo chuột, bấm đúp, `Shift`+click, `Shift`+phím mũi tên, `Ctrl+A`): đọc vùng chọn bằng UI Automation, không bao giờ dùng `Ctrl+C`; chương trình nào không cho đọc vùng chọn thì không có danh sách (phím tắt vẫn dùng được). Danh sách tự hiện chỉ nhận `Alt+1`...`Alt+0`, nhấn phím tắt để dùng thêm ↑ ↓ Enter Esc; tự ẩn sau 20 giây, khi bấm phím khác, bấm chuột chỗ khác, cuộn chuột hoặc đổi chương trình. Không đọc trong terminal, ô mật khẩu và cửa sổ của VOpenKey AI. Tắt ở "Gợi ý, snippet và công cụ..." | `Ctrl+Alt+C` |
| Khôi phục từ | Trả lại phím đã gõ cho từ không phải tiếng Việt (`restore` đừng thành `rétỏe`). Tự động khi hết từ, hoặc bằng phím tắt | `Ctrl+Alt+R` |
| Trợ lý AI | Cửa sổ viết văn bản bằng OpenAI, Gemini, Claude, DeepSeek, Qwen, OpenRouter, Ollama, LM Studio, máy chủ tương thích OpenAI, hoặc **chương trình AI đã đăng nhập sẵn trên máy** (Codex CLI, Claude Code CLI, Antigravity CLI: không cần API key, chạy trong thư mục tạm trống, chỉ viết chữ; xem bên dưới). Key được mã hoá bằng tài khoản Windows (DPAPI). `Ctrl+Enter` tạo, `Ctrl+Shift+Enter` chèn vào chỗ đang gõ, `Ctrl+Shift+C` sao chép rồi đóng cửa sổ | `Ctrl+Alt+A` |
| Gõ tắt phổ biến | Nút "Thêm gõ tắt phổ biến" thêm `ko`, `dc`, `vs`... mà không ghi đè gõ tắt của bạn | |

### Dùng Codex, Claude Code, Antigravity làm AI
Trong **Cài đặt AI > Dịch vụ AI** chọn "Codex CLI", "Claude Code CLI" hoặc "Antigravity CLI". Các chương trình này tự đăng nhập (`codex login`, `claude auth login`...), VOpenKey AI không thấy tài khoản hay token, chỉ chạy chương trình một lần cho mỗi yêu cầu, trong một thư mục tạm trống rồi xoá. Chế độ chỉ viết chữ: bỏ cấu hình, hook, MCP của riêng bạn, không công cụ, không ghi tệp, không lưu phiên (Codex: `exec --ignore-user-config -s read-only --disable shell_tool --ephemeral`; Claude: `-p --safe-mode --tools "" --no-session-persistence`); chữ của bạn đi vào đầu vào chuẩn, không nằm trong tham số dòng lệnh (riêng Antigravity chỉ nhận qua tham số, và Windows giới hạn khoảng 30.000 ký tự). Chương trình được tìm trong `PATH` và các thư mục hay cài (`%APPDATA%\npm`, `%USERPROFILE%\.local\bin`, scoop, WinGet...) hoặc bấm **Chọn...** để chỉ tệp. Chọn được model (bấm **Tải danh sách**; để trống là model nhẹ) và mức suy nghĩ (mặc định mức thấp, nhanh nhất). Một tệp `.exe` chạy trực tiếp; một tệp script `.cmd` (cách npm cài Codex) chạy qua `cmd.exe` và chỉ khi không có ký tự `& | < > ^ % !` hay xuống dòng trong tham số: Codex qua `.cmd` chạy được, còn Claude Code (lời dặn nhiều dòng) và Antigravity cần tệp `.exe` (`claude.exe` của bản cài chính thức của Anthropic). Antigravity CLI tự lưu mỗi lần hỏi thành một cuộc trò chuyện trong thư mục của nó, VOpenKey AI không xoá được.

**Tạo ảnh** (chỉ khi chọn Codex CLI): mô tả bức ảnh vào ô yêu cầu rồi bấm **Tạo ảnh** (`Ctrl+Alt+Enter`). VOpenKey AI nhờ Codex dùng kỹ năng `$imagegen` của nó bằng câu "Use $imagegen skill to create picture {mô tả}, follow our design system." (không nhắc tên kỹ năng thì ảnh rất tệ; sửa câu này ở Cài đặt AI > **Lệnh tạo ảnh**, `{prompt}` là chỗ đặt mô tả). Ảnh dùng model và mức suy nghĩ đang chọn, thường mất 20 đến 40 giây, hiện ngay trong cửa sổ (bấm vào ảnh để xem lớn); `Ctrl+Shift+Enter` chèn ảnh vào ứng dụng đang gõ (dán bằng `Ctrl+V`, clipboard của bạn được trả lại), `Ctrl+Shift+C` sao chép ảnh rồi đóng, **Lưu vào Downloads**, **Hiện file ảnh** trong Explorer. Codex tự lưu file ở `%USERPROFILE%\.codex\generated_images\` (hoặc `%CODEX_HOME%`), VOpenKey AI không xoá; mỗi lần tạo ảnh nạp khoảng 110 nghìn token đầu vào (phần lớn được cache). Ảnh có phần trong suốt được đặt lên nền trắng trong cửa sổ và trong clipboard dạng bitmap; chương trình biết định dạng "PNG" thì nhận bản gốc.

Chưa có trên Windows: AI chạy trên máy do VOpenKey AI tự cài (hãy cài Ollama hoặc LM Studio rồi chọn trong Cài đặt AI).

Dữ liệu nằm ở `%APPDATA%\VOpenKey` (từ điển, từ đã học, snippet); cài đặt ở registry như các cài đặt cũ.

### Cập nhật
VOpenKey AI tự hỏi GitHub (file `version.json` của nhánh `master`) xem có bản Windows mới không: sau khi mở khoảng 15 giây, rồi vài giờ một lần, ở một luồng riêng nên không làm chậm bàn phím. Có bản mới thì hỏi bạn một lần; chọn **Có** thì `OpenKeyUpdate.exe` tải `VOpenKey-<phiên bản>-Windows.zip` của bản phát hành, **kiểm tra mã SHA-256** của nó với file `.sha256` đi kèm (sai là bỏ, không cài), thay `OpenKey64.exe` / `OpenKey32.exe` (giữ bản cũ nếu không thay được) rồi mở lại chương trình. Tắt ở Bảng điều khiển > Hệ thống > "Tự động kiểm tra bản mới" (mặc định bật); nút "Kiểm tra bản mới..." kiểm tra ngay. Windows không thay được file đang chạy nên việc cài luôn cần đóng chương trình vài giây, khác với macOS (cài ngay khi khởi động lại). `version.json` chỉ được ghi sau khi file zip đã nằm trên bản phát hành (xem `RELEASING.md`), nên người dùng Windows không bao giờ được mời cập nhật khi chưa có file.

## Cài đặt
- Vào [đây](https://github.com/ntanvinh/OpenKey/releases/latest) tải file `VOpenKey-<phiên bản>-Windows.zip` mới nhất về máy, giải nén vào nơi bất kỳ.
- Nhấp đúp vô `OpenKey64.exe` (Windows 64 bit) hoặc `OpenKey32.exe` (Windows 32 bit) để chạy chương trình.
- Lưu ý, khi chạy chương trình lần đầu, Windows sẽ mở một hộp thoại để hỏi bạn, bấm `yes` để đồng ý VOpenKey AI chạy với quyền `admin`
- Xong rồi một biểu tượng chữ `V` sẽ hiện trên system tray, đúp click vô đó để mở bảng điều khiển, cấu hình những thứ bạn cần.
- Xong.
## Một số hình ảnh khác
![Menu](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/win32_5.png "Menu")
![Bảng gõ tắt](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/win32_2.png "Macro table")
![Công cụ chuyển mã](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/win32_3.png "Convert tool")

## Thông tin
- Dự án OpenKey ra đời vào ngày 18/01/2019. OpenKey được viết lại hoàn toàn mới bởi tác giả Mai Vũ Tuyên. Mục đích ra đời của OpenKey là để khắc phục lỗi gạch chân khó chịu do cơ chế `preedit` gây ra trên hệ điều hành macOS
- Phiên bản đầu tiên cho hệ điều hành macOS được phát hành trên Github vào ngày 01/02/2019  
Trải qua nhiều lần cập nhật và phát triển, ngày 31/07/2019, OpenKey cho macOS được mọi người biết đến qua trang tinhte.vn  
- Với nhiều ý kiến đóng góp từ cộng đồng, OpenKey cho macOS phát triển tới phiên bản 1.5 đã đầy đủ các tính năng của một bộ gõ chuẩn, tiện lợi.  
- Ngày 19/09/2019 tác giả đã "port" OpenKey cho hệ điều hành Windows, phát triển song song với phiên bản cho macOS.  
- Phiên bản OpenKey cho Linux vẫn đang âm thầm phát triển, vì Linux có hệ thống GUI phức tạp, API "lạ" nên đòi hỏi thời gian nhiều hơn cho việc phát triển.

## Mã nguồn
- Mã nguồn cho Windows được build thành công với Microsoft Visual Studio 2017 trở lên (workflow `windows-build.yml` build x86 và x64 bằng Visual Studio 2022).
- Trên Mac hoặc Linux có thể kiểm tra cú pháp và link bằng mingw-w64: `scripts/check-windows.sh`, `scripts/link-windows.sh`; test phần dùng chung: `scripts/test-portable.sh`. Những lệnh này không chạy được chương trình Windows.
## Giấy phép
OpenKey for Windows được phát hành dưới giấy phép GPL, điều này nghĩa là bạn hoàn toàn có thể tự do tải mã nguồn về chỉnh sửa, cải tiến theo mục đích của bạn. Nếu bạn tái phân phối bản cải tiến của bạn, bạn **phải** công bố mã nguồn và credit OpenKey bản gốc.

## Một điều nữa
Đừng quên ủng hộ tác giả bằng cách mua ly cafe cho tác giả tỉnh ngủ nhé: [Gửi cafe](https://paypal.me/tuyenmai)  
Hoặc trực tiếp qua ví momo:   
![Donate by momo](https://tuyenvm.github.io/images/momo.png "Momo").   
Cảm ơn các bạn.