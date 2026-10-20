# Kịch bản dữ liệu cho ảnh chụp VOpenKey AI (desktop)

Mỗi ảnh bán đúng **một** tính năng trong `marketing/features/*.json`. Thứ tự ảnh = thứ tự website (nhóm `unique` → `value` → `common`, rồi `rank`), để ảnh trên website lssoft nằm đúng chỗ của tính năng được quảng cáo. VApp Manager cho tối đa 8 ảnh, nên chỉ 8 tính năng đầu được chụp; 8 tính năng còn lại có kịch bản ở cuối file để dùng khi đổi hoặc nâng giới hạn.

Dùng chung cho hai cách làm:

- **AI tự chụp** (🤖): cửa sổ riêng của app, không cần gõ phím thật.
- **Người chụp rồi dán** (🧑): cần gõ thật, phím tắt thật hoặc chụp một vùng. Làm đúng kịch bản, chụp bằng ⌘⇧4 (giữ thêm ⌃ để ảnh vào clipboard rồi dán vào VApp Manager), hoặc lưu thành `NN-<feature-id>.png`.

Tên tệp: `marketing/screenshots/desktop/NN-<feature-id>.png`. Sau khi có ảnh mới đặt `image` = `../screenshots/desktop/NN-<feature-id>.png` trong feature tương ứng. **Chưa có ảnh nào, chưa sửa feature nào.**

## Quy tắc chung

1. **Một người dùng xuyên suốt:** Lan, bán cà phê rang xay online, tự viết tin nhắn cho khách và bài blog bằng tiếng Việt. Khách là "chị Mai". Không đặt tên thương hiệu cho quán (tên bịa dễ trùng thương hiệu thật).
2. **Dữ liệu thật, không giả:** kết quả AI phải do AI trả lời thật trong lúc chụp, không gõ tay. Không lorem ipsum, "Test 1", ô trống, thông báo lỗi.
3. **Không lộ riêng tư:** tên tài khoản macOS (đường dẫn `/Users/<tên>`), API key, ứng dụng hay tài liệu riêng của chủ máy. Chụp trong tài khoản macOS demo, hoặc kiểm từng ảnh trước khi nhận.
4. **Chỉ chụp cửa sổ** (`screencapture -x -o -l <window id>`), không chụp vùng màn hình khi AI làm, vì vùng có thể lấy cả nội dung riêng đang mở. Người chụp vùng thì tự đóng mọi cửa sổ khác.
5. **Bản test, không đụng bản thật:** AI dùng bundle id `vn.io.lssoft.vopenkey.uitest` và dọn sau khi chụp. Thư mục `~/Library/Application Support/VOpenKey/` (snippet, gợi ý đã học) **dùng chung với bản thật**: không thêm dữ liệu demo vào đó, không để lại file.
6. **Cỡ ảnh:** VApp Manager yêu cầu tối thiểu 800 px rộng. Cửa sổ Cài đặt rộng 560 pt, retina ra khoảng 1120 px, đạt mức này nhưng thấp hơn mức 1600 px mà prompt của VApp Manager khuyên.
7. **Ngôn ngữ giao diện:** app chỉ có giao diện tiếng Việt, trong khi `product.json` ghi ảnh media là `en-US`. Mọi ảnh sẽ hiện chữ Việt. Cần chủ xác nhận (xem cuối file).

## Thứ tự và người chụp

| NN | Tính năng | Cửa sổ chụp | Ai chụp |
|----|-----------|-------------|---------|
| 01 | ai-writing-assistant | Trợ lý AI | 🧑 (cần AI đã kết nối + vùng chọn thật) |
| 02 | local-ai-setup | Cài AI chạy trên máy | 🤖 |
| 03 | signed-in-ai-agents | Cài đặt › AI | 🤖 (cần Codex CLI đã đăng nhập) |
| 04 | ai-image-generation | Trợ lý AI (Codex CLI) | 🧑 (tốn lượt Codex, hỏi chủ trước) |
| 05 | prompt-snippet-library | Bảng snippet | 🧑 (phím tắt thật) |
| 06 | restore-accidental-typing | Cài đặt › Bộ gõ | 🤖 |
| 07 | contextual-word-suggestions | Thanh gợi ý trên TextEdit | 🧑 (gõ thật + chụp vùng) |
| 08 | smooth-vietnamese-typing | Hai cửa sổ TextEdit cạnh nhau | 🧑 (gõ thật + chụp vùng) |

## 01 · ai-writing-assistant — "Soạn cùng AI bạn chọn"

- **Phải thấy ngay:** một đoạn nháp đã chọn trong app đang dùng, được đưa vào hộp thoại, và bản viết lại sẵn sàng để chèn thay vùng chọn.
- **Cửa sổ:** panel "Trợ lý AI" (mở bằng ⌃⌥A khi đang chọn chữ trong TextEdit).
- **Dữ liệu:**
  - Dòng đầu (yêu cầu): `Viết lại lịch sự hơn, giữ nguyên ý, tối đa 3 câu`
  - Đoạn đã chọn, bên dưới dòng đầu: `Chị Mai ơi, đơn cà phê tháng này bên em giao trễ 2 ngày vì lô hạt về chậm, em xin lỗi chị nha. Chị muốn nhận phần có sẵn hôm nay hay đợi đủ lô mới ạ?`
  - Dòng trạng thái đúng như app hiện: `Đã lấy N ký tự đang chọn. Gõ yêu cầu ở dòng đầu; kết quả sẽ thay thế vùng chọn.`
  - Khung "Kết quả": câu trả lời thật của AI, bằng tiếng Việt, lịch sự, không quá 3 câu, cuối là `Xong. ⇧⌘↩ để dùng kết quả.`
  - Dòng `Nội dung gửi tới … · <model>` hiện rõ nhà cung cấp đang dùng, không để `Chưa kết nối AI`.
- **Không được:** để ảnh gợi ý rằng mọi kết nối AI đều chạy trên máy; dòng "Chạy trên máy này…" chỉ hiện khi thật sự dùng AI chạy trên máy.

## 02 · local-ai-setup — "Chạy AI trên Mac của bạn"

- **Phải thấy ngay:** app kiểm tra máy rồi mới khuyên model, và chữ không rời máy.
- **Cửa sổ:** "Cài AI chạy trên máy" (mở từ Cài đặt › tab AI).
- **Dữ liệu:** không gõ gì. Giữ nguyên câu `Chạy AI ngay trên Mac: không cần API key, chữ của bạn không rời máy.`, khung "Máy của bạn" và model có nhãn `★ Khuyên dùng` đang được chọn, để thấy dòng `Chất lượng … Tốc độ … Tiếng Việt: …` và `Tải … · RAM … (máy bạn …)`. Số liệu do bộ tư vấn tính theo máy chụp, **không sửa tay**.
- **Chụp khi:** máy rảnh, cắm điện (pin yếu hay máy bận làm hiện cảnh báo, đúng thực tế nhưng làm ảnh kém sạch).
- **Không được:** bấm Cài đặt, tải hay cài gì (VApp Manager cấm cài thêm phần mềm); không nhập tên model tự do.

## 03 · signed-in-ai-agents — "Dùng AI bạn đã đăng nhập"

- **Phải thấy ngay:** không có ô API key, chỉ có chương trình đã đăng nhập sẵn trên máy, model và mức suy nghĩ.
- **Cửa sổ:** Cài đặt › tab AI.
- **Dữ liệu:** nhà cung cấp `Codex CLI (ChatGPT)`; mục `Chương trình đã đăng nhập sẵn trên máy` hiện dòng `Chương trình` với đường dẫn đã tìm thấy; model và `Mức suy nghĩ` để mặc định (model nhẹ, mức thấp nhất mà model nhận). Các hàng API key và địa chỉ phải đang ẩn. Nếu Codex CLI chưa đăng nhập trên máy chụp thì dừng, không dựng ảnh giả.
- **Cẩn thận:** hàng `Chương trình` có thể hiện đường dẫn đầy đủ với tên tài khoản. Chụp trong tài khoản demo, hoặc đừng nhận ảnh nếu thấy tên thật.

## 04 · ai-image-generation — "Tạo ảnh từ mô tả"

- **Phải thấy ngay:** mô tả ở trên, ảnh vừa tạo hiện trong hộp thoại, kèm `Chèn ảnh`, `Lưu`, `Hiện ảnh`.
- **Cửa sổ:** panel "Trợ lý AI" với `Codex CLI (ChatGPT)` đã chọn (nút `Tạo ảnh` chỉ dùng được với Codex).
- **Dữ liệu:**
  - Mô tả: `Ảnh bìa cho bài blog về cách pha cà phê phin buổi sáng: ly phin đặt trên bàn gỗ cạnh cửa sổ, nắng sớm, phong cách minh họa phẳng, tông nâu kem`
  - Ảnh: Codex tạo thật một lần (khoảng 25 giây, tốn lượt Codex của chủ). Nhận ảnh khi không có chữ lỗi, logo, người thật.
  - Dòng cuối: `Xong. ⇧⌘↩ để chèn ảnh. Codex lưu ảnh ở ~/…` (app viết đường dẫn dạng `~/`, không lộ tên tài khoản).
- **Hỏi chủ trước khi chạy:** tạo ảnh dùng hạn mức Codex của họ.

## 05 · prompt-snippet-library — "Dùng lại prompt mọi nơi"

- **Phải thấy ngay:** gõ không dấu mà vẫn ra đúng prompt tiếng Việt, kèm xem trước nội dung.
- **Cửa sổ:** bảng snippet (⌃⌥S), ô `Tìm snippet…`.
- **Dữ liệu:** gõ `tom tat` (không dấu) vào ô tìm. Dòng đầu phải là `Tóm tắt văn bản` và khung xem trước hiện nội dung prompt đó, đúng như app hiện. Các dòng bên dưới là kết quả thật của app, **kiểm khi chụp** thay vì đoán.
- **Dùng 21 snippet mẫu có sẵn**, không thêm snippet riêng (thư mục dữ liệu dùng chung với bản thật, xem quy tắc 5).
- **Chưa kiểm chứng:** phím thật vào panel không kích hoạt (nonactivating) khi app khác đang ở trước, từng ghi nhận là chưa test được từ shell.

## 06 · restore-accidental-typing — "Khôi phục từ khi đang gõ"

- **Phải thấy ngay:** từ `rétỏe` tự trả về `restore`, và có phím khôi phục thủ công.
- **Cửa sổ:** Cài đặt › tab Bộ gõ, cuộn tới mục "Chính tả và dấu" cho thấy đủ hai hàng.
- **Dữ liệu:** `Chế độ gõ` = Tiếng Việt, `Kiểu gõ` = Telex. Bật `Tự khôi phục từ không phải tiếng Việt`, với dòng mô tả ví dụ `rétỏe` → `restore` đọc được. `Phím khôi phục từ đang gõ` = `⌥Space`. Giữ các công tắc khác ở trạng thái mặc định.
- **Không có ảnh phụ trong TextEdit:** kết quả cuối của `restore` trông như chữ Anh bình thường, một ảnh tĩnh không thể hiện việc từ vừa được trả lại. Dòng mô tả `rétỏe` → `restore` trong Cài đặt mới là thứ truyền đạt tính năng.

## 07 · contextual-word-suggestions — "Gợi ý từ khi đang gõ"

- **Phải thấy ngay:** thanh gợi ý nằm dưới chữ đang gõ, với `thiết kế` ở vị trí đầu. (Theo Cài đặt, từ đầu chọn bằng Tab, các từ khác bằng ⌥1–⌥5.)
- **Cửa sổ:** TextEdit đang gõ, chụp vùng quanh cửa sổ đó **kèm thanh gợi ý** (thanh là panel riêng, `screencapture -l` của cửa sổ TextEdit không có nó).
- **Dữ liệu:** bật `Thanh gợi ý khi gõ` trong Cài đặt › Gợi ý. Gõ `Chị Mai xem giúp em bản ` rồi gõ liền `thietke` (không dấu, chưa bấm cách). Thanh phải hiện `thiết kế` (từ ghép đã kiểm chứng trong engine).
- **Kiểm lúc chụp:** từ điển Wiktionary không có tần suất nên đôi khi chen mục hiếm. Nếu cột đầu lạ, thử cụm khác và chọn theo thứ nhìn thấy, đừng chọn theo giả định.
- **Phương án AI chụp thay thế (yếu hơn):** Cài đặt › tab Gợi ý với `Thanh gợi ý khi gõ` bật.

## 08 · smooth-vietnamese-typing — "Gõ tiếng Việt không bị gạch chân"

- **Phải thấy ngay:** cùng một từ đang gõ dở: có gạch chân ở bộ gõ có sẵn của macOS, không gạch chân ở VOpenKey AI.
- **Cửa sổ:** hai cửa sổ TextEdit cạnh nhau (trái: bộ gõ Vietnamese Telex có sẵn của macOS; phải: bộ gõ ABC + VOpenKey AI bật), chụp vùng quanh cả hai.
- **Dữ liệu:** cả hai gõ cùng câu `Sáng nay mình pha cà phê phin rồi ngồi viết` và **dừng lại** khi từ cuối đang gõ dở (Telex `vieets`, chưa bấm dấu cách), để thấy gạch chân ở bên trái.
- **Cẩn thận:** đây là ảnh so sánh với bộ gõ có sẵn của macOS. README của dự án có nói về lỗi gạch chân nhưng `marketing/positioning.md` ghi mọi so sánh vượt README là chưa kiểm chứng. Chỉ dùng khi chủ chụp được trên máy thật và đồng ý. Nếu không, dùng ảnh phụ: Cài đặt › Ứng dụng › "Tương thích" với `Sửa lỗi gợi ý` bật.

## Dự trữ: 8 tính năng còn lại (chưa có ảnh vì giới hạn 8)

| NN | Tính năng | Cửa sổ | Dữ liệu cần thấy |
|----|-----------|--------|------------------|
| 09 | custom-text-macros | Cửa sổ Gõ tắt | Thêm bộ mẫu bằng nút `Gõ tắt mẫu…`; thấy `mn` → `mọi người`, `hnay` → `hôm nay`, `tks` → `cảm ơn` (có trong `vi-macros.txt`). Kiểm bản test không ghi vào dữ liệu gõ tắt của bản thật. |
| 10 | convert-vietnamese-encodings | Công cụ chuyển mã | Cửa sổ này chỉ có hai ô bảng mã, các tuỳ chọn và nút Chuyển, làm việc trên clipboard, **không có vùng hiện chữ**. Chụp với nguồn = TCVN3, đích = Unicode. Muốn thấy chữ lỗi chuyển thành chữ đúng thì cần ảnh 🧑 hai cửa sổ: TextEdit cạnh công cụ. Sao chép `Chúc mừng năm mới`, chuyển Unicode → TCVN3 bằng công cụ (kết quả vào clipboard, dán vào TextEdit), rồi `Đổi chỗ bảng mã nguồn và đích` và chuyển lại. Không gõ tay chuỗi mã cũ để khỏi sai. |
| 11 | remember-input-settings-by-app | Sheet "Ứng dụng đã ghi nhớ" | 3–4 app của Apple (Notes, Safari, TextEdit, Terminal) với chế độ gõ và bảng mã khác nhau, thêm bằng `Thêm ứng dụng`. Bản test có thể rỗng nếu thiếu quyền: kiểm, không giả. |
| 12 | flexible-vietnamese-input | Cài đặt › Bộ gõ, mục "Kiểu gõ" | `Kiểu gõ` Telex, `Bảng mã` Unicode, hai ô đang đóng (menu thả xuống không chụp được bằng `-l`). Cuộn khác ảnh 06. |
| 13 | writing-controls | Cài đặt › Bộ gõ, mục "Chính tả và dấu" | `Kiểm tra chính tả`, `Đặt dấu oà, uý`, `Viết hoa chữ cái đầu câu` bật; khác ảnh 06 ở chỗ cuộn và công tắc nổi bật. |
| 14 | keyboard-shortcuts | Menu thanh trạng thái | Menu liệt kê phím tắt `Snippet…` và `Trợ lý AI…` cạnh phím chuyển chế độ. Menu không chụp được bằng AI: 🧑 chụp vùng. Thay thế: Cài đặt › Bộ gõ, hàng `Phím chuyển chế độ`. |
| 15 | macos-menu-controls | Cài đặt › Hệ thống, mục "Khởi động và hiển thị" | `Khởi động cùng macOS`, `Hiện biểu tượng trên thanh Dock`, `Biểu tượng đơn sắc trên thanh menu`. |
| 16 | open-source-project | Cửa sổ About | Biểu tượng, tên, phiên bản **thật của bản đang chạy**, thẻ LSSoft và phần credits, đúng như app hiện (không thêm chữ). |

## Cần chủ quyết định trước khi chụp

1. **Ảnh toàn chữ Việt hay không:** `product.json` ghi media `en-US`, nhưng app không có giao diện tiếng Anh. Giữ nguyên (ảnh tiếng Việt, đúng với sản phẩm) hay có kế hoạch khác?
2. **Ảnh 04 tốn lượt Codex** (khoảng 25 giây, một lần) và ảnh 01, 03 cần một AI đã đăng nhập trên máy chụp.
3. **Ảnh 08 là ảnh so sánh** với bộ gõ có sẵn của macOS (xem cảnh báo trong mục đó).
4. **Tài khoản demo:** chụp 03 và 04 trong tài khoản macOS riêng cho demo, hay chủ tự kiểm từng ảnh để không lộ tên tài khoản.

## Điều tôi chưa làm hoặc chưa kiểm chứng

- Chưa chạy app, chưa chụp ảnh nào, chưa sửa `features/*.json`. File này chỉ là kịch bản.
- Nhãn giao diện lấy từ mã nguồn (`AIAssistant.m`, `SettingsWindowController.m`, `SnippetPalette.m`, `AILocalSetupController.m`, `ConvertToolViewController.mm`, `RememberedAppsController.m`). Thứ tự dòng của bảng snippet, danh sách gợi ý và kết luận của bộ tư vấn máy chỉ biết được khi chụp.
- Các ca gõ lấy từ test của engine (`restore_test.cpp`: `restore` → `rétỏe` → `restore`) và ghi chú dự án (`thietke` → `thiết kế`). Chuỗi Telex `vieets` và các câu mẫu ở ảnh 01, 07, 08 chưa chạy qua engine; kiểm kết quả trên màn hình lúc chụp.
- Phần nào trong Cài đặt/cửa sổ nằm ở tab hay mục nào lấy từ mã (`SettingsWindowController.m`); ba tính năng dự trữ 12, 13, 14 dùng chung tab Bộ gõ nên khi chụp phải khác nhau ở công tắc nổi bật và vị trí cuộn.
