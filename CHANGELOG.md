# OpenKey Change Log

##### VOpenKey 3.0.0 (build 50): (14/10/2026)
- Thanh gợi ý khi gõ theo phong cách macOS (chất liệu menu, bo góc đồng tâm, sáng/tối tự theo hệ thống), kiểu bảng ứng viên của bộ gõ Hán tự: hiện các từ có thể gõ tiếp ngay dưới từ đang gõ. Tab chọn từ đầu, ⌥1–⌥5 chọn từ khác; chọn xong tự thêm dấu cách và dự đoán từ kế tiếp. Mặc định tắt, bật trong Cài đặt > Gõ tắt.
- Engine gợi ý dùng chung cho mọi nền tảng (`engine/Suggest*.{h,cpp}`): từ điển là file text, đoán theo ngữ cảnh 2 từ trước (bigram/trigram), gõ không dấu vẫn ra từ có dấu, tự học từ cách gõ (lưu ở `~/Library/Application Support/VOpenKey/learned.txt`).
- Gợi ý từ ghép: gõ liền không dấu, ví dụ `thietke`, ra `thiết kế`; gõ dở như `thiet` ra `thiết kế`, `thiết bị`... Từ ghép viết `thiết_kế` trong file từ điển, hoặc viết cách bình thường dưới dòng `#!compounds`. Tìm cả bằng phím thô khi Telex đã đổi chữ trên màn hình (`hoso` ra `hồ sơ`).
- Phát hành bằng một lệnh: `scripts/release.sh patch` (hoặc `minor`, `major`, số cụ thể) tự nâng phiên bản ở mọi nơi, build, ký, notarize, đẩy lên GitHub Release, chờ bản Windows do GitHub Actions build, rồi mới báo bản mới trong `version.json`. Thêm `scripts/version.sh`.
- Windows: nâng phiên bản lên 3.0.0; kiểm tra bản mới và cập nhật trỏ về repo VOpenKey (`version.json`, `VOpenKey-<phiên bản>-Windows.zip` trong Release `v<phiên bản>`); thêm workflow `Release Windows` và hướng dẫn `RELEASING.md`. Thanh gợi ý khi gõ chưa có trên Windows.
- Biểu tượng: thay các ảnh PNG đen cũ trong cửa sổ Chuyển mã và Gõ tắt bằng SF Symbols của macOS (tự đổi màu theo giao diện sáng/tối); nút, ô chọn bảng mã và ô nhập dùng kiểu bo tròn chuẩn của macOS; "Chuyển mã" là nút mặc định.
- Sửa lỗi hàng trong Cài đặt có mô tả dài bị tràn ra ngoài thẻ; sửa công tắc con của "Thanh gợi ý" hiện Tắt khi mở Cài đặt trước khi bộ gợi ý khởi động.
- Cài đặt: khoảng cách các hàng, nhóm và tiêu đề thống nhất ở mọi tab (hàng cao tối thiểu 44 pt, đường kẻ thụt như System Settings, chú thích dưới nhóm); thêm nút xóa dữ liệu đã học.
- Kèm sẵn khoảng 36.000 từ ghép và 5.000 âm tiết từ [Wiktionary tiếng Việt](https://vi.wiktionary.org) (CC BY-SA 4.0, chỉ lấy tên mục từ), tạo bằng `scripts/fetch-wiktionary-dictionary.py`; ghi nguồn trong cửa sổ About và `engine/dictionaries/README.md`.
- Bổ sung từ điển bằng cách thả file `.txt` vào thư mục Dictionaries; `scripts/build-dictionary.py` tạo từ điển lớn từ văn bản tiếng Việt.

##### VOpenKey 2.1.0 (build 49): (13/10/2026)
VOpenKey là bản fork của OpenKey 2.0.4 do LSSoft phát triển.
- Đổi tên thành VOpenKey, bundle ID `vn.io.lssoft.vopenkey`. Lần đầu mở sẽ tự nhập cài đặt từ OpenKey gốc.
- Giao diện làm lại theo phong cách macOS: menu thanh trạng thái, cửa sổ Cài đặt (tab trên toolbar, nhóm tùy chọn, công tắc), About chuẩn của macOS ghi rõ LSSoft fork từ tác giả gốc.
- Cửa sổ cấp quyền khi mở lần đầu: bật công tắc Trợ năng và Giám sát đầu vào, app tự chạy tiếp, không cần mở lại.
- Xử lý Secure Input (ô mật khẩu, Secure Keyboard Entry): biểu tượng chuyển sang E khi app đang gõ giữ Secure Input; tự dùng bộ gõ Vietnamese của macOS khi app khác chạy nền giữ.
- Sửa lỗi OpenKey không gõ được nữa sau khi macOS tự tắt event tap.
- "Khởi động cùng macOS" dùng cơ chế mới của macOS (không cần helper).
- Kiểm tra bản mới trỏ về repo của VOpenKey, "Có" mở trang tải về; sửa lỗi nút kẹt ở "Đang kiểm tra..." khi mất mạng.
- Yêu cầu macOS 13 trở lên. Thêm `scripts/dev.sh` và `scripts/release.sh` (ký, notarize, đóng gói dmg, đăng GitHub Release).

##### OpenKey for Linux: (in development)

##### Version 1.2 RC5: (26/08/2019)
- Sửa lỗi không gõ được chữ "quởn".
- Không kiểm tra chính tả khi sử dụng dấu "[ ] { }".

##### Version 1.2 RC4: (24/08/2019)
- Bảng gõ tắt tiện lợi hơn, thêm tính năng Sửa từ.
- Cải thiện khả năng bỏ dấu, tốc độ nhanh hơn.
- Tự phục hồi dấu câu khi xóa ký tự (chữ “tuỳa” xóa “a” sẽ thành “tùy”,… )
- Sửa lỗi không gõ được từ “quét” khi bật chức năng tự phục hồi phím.
- Sửa lỗi ư và ơ khi gõ font Palatino trong MS Word.
- Sửa lỗi bảng mã VNI khi xóa ký tự, không thể gõ tiếng việt tiếp.

##### Version 1.2 RC3: (16/08/2019)
- Không gõ được "dui9, duoi96".
- Không gõ được "tuyps".

##### Version 1.2 RC2: (15/08/2019)
- Sửa lỗi không gõ được d i e u 9 6.
- Sửa lỗi không gõ tắt được khi dùng chế độ tiếng Anh với từ bắt đầu bằng.
- Sửa lỗi tự nhảy dấu khi gõ sai.
- Thêm thông tin phiên bản trong bảng giới thiệu.

##### Version 1.2 RC1: (13/08/2019)
- Chuyển chế độ thông minh: Bạn đang dùng chế độ gõ Tiếng Việt trên ứng dụng A, bạn chuyển qua ứng dụng B trước đó bạn dùng chế độ gõ Tiếng Anh, OpenKey sẽ tự động chuyển qua chế độ gõ Tiếng Anh cho bạn, khi bạn quay lại ứng dụng A, OpenKey tất nhiên sẽ chuyển lại chế độ gõ tiếng Việt, rất cơ động.
- Viết Hoa chữ cái đầu câu: Khi gõ văn bản dài, đôi khi bạn quên ghi hoa chữ cái đầu câu khi kết thúc một câu hoặc khi xuống hàng, tính năng này sẽ tự ghi hoa chữ cái đầu câu cho bạn, thật tuyệt vời.
Khôi phục phím với từ sai: hỗ trợ thêm các dấu ngắt câu như dấu chấm, phẩy,...
Sửa vài lỗi nho nhỏ khác.

##### Version 1.1 RC: (12/08/2019)
- Chế độ “Gửi từng phím”: OpenKey bản mới (1.1) mặc định dùng kỹ thuật mới gửi dữ liệu 1 lần thay vì gửi nhiều lần cho chuỗi ký tự, nên nếu có ứng dụng nào không tương thích, hãy bật tính năng này lên, mặc định thì nên tắt vì kỹ thuật mới sẽ chạy nhanh hơn.
- Phục hồi phím với từ sai.
- Nâng cao khả năng check chính tả.
- Sửa lỗi thanh địa chỉ trình duyệt (on/off).
- Bỏ tính năng "cho phép bỏ dấu tự do".
- Gõ tắt: bao gồm bật/tắt, bảng soạn các từ gõ tắt, hỗ trợ ký tự bất kỳ, bảng mã bất kỳ. Khi soạn thảo các từ gõ tắt, bạn phải nhập ở bảng mã Unicode dựng sẵn.
- Gõ tắt ngay khi trong chế độ gõ tiếng Anh (on/off).
- Sửa lỗi trên một số phần mềm.

##### Version 1.0.20: (06/08/2019)
- Sửa lỗi phím tắt chuyển chế độ, phím tắt của ứng dụng khác vẫn hoạt động nếu bị trùng.
- Cho phép gõ “Đ” ngay sau phụ âm.
- Không hiện Icon trên thanh Dock mục recent app.
- Sửa lỗi “oăc” ra “ooạc” trong kiểu gõ VNI.
- Sửa vài lỗi nhỏ xíu khác.

##### Version 1.0.19: (04/08/2019)
- Sửa lỗi không gõ được chữ “gì” khi dùng bỏ dấu kiểu cũ.
- Sửa lỗi không gõ được Unicode tổ hợp trên ứng dụng Stickies.
- Sửa lỗi gõ các âm "oong, ooc".

##### Version 1.0.18: (01/08/2019)
- Không sử dụng w -> ư trong Simple Telex.
- Bật tắt kêu beep khi chuyển chế độ.
- Thêm phím chuyển Shift, giờ có thể sử dụng Ctrl + Shift hoặc Command + Shift.
- Sửa vài lỗi khác.
- Hỗ trợ cho macOS bản cũ.

##### Version 1.0.17: (31/07/2019)
- Add Simple Telex mode.
- Black/White icon on menu bar.
- Space and back key improved.
- Modern orthography.
- Custom switch key.
- Quick telex (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- Support TextWrangler.

##### Version 1.0.14: (09/04/2019)
- Add case "uýt".
- Improve typing English in Vietnamese mode.

##### Version 1.0.11: (27/02/2019)
- Add case "chú thòong", "gòong".

##### Version 1.0.10: (26/02/2019)
- Fix case "duocd".

##### Version 1.0.9: (22/02/2019)
- Fix incorrect word when switch language without pressing Space key.

##### Version 1.0.8: (19/02/2019)
- Switch key: Control + Command + Space  --> Control + Z

##### Version 1.0.7: (15/02/2019)
- Fix case "duongd".
- Fix end consonant "t".

##### Version 1.0.6: (15/02/2019)
- Fix case "quatw".

##### Version 1.0.5: (13/02/2019)
- Spelling enhanced.
- Correct 1x menu icon.

##### Version 1.0.3: (11/02/2019)
- Fix auto correct on Chrome.

##### Version 1.0: (11/02/2019)
- First release.



# OpenKey lịch sử

##### Version 1.0.17: (31/07/2019)
- Thêm chế độ Simple Telex.
- Icon trắng đen trên menu bar.
- Lỡ bấm phím Space, xoá space vẫn có thể bỏ dấu.
- Bỏ dấu kiểu cũ/mới: òa, úy | oà, uý.
- Tuỳ chọn phím chuyển.
- Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- Hỗ trợ TextWrangler.

##### Version 1.0.11: (27/02/2019)
- Thêm trường hợp "chú thòong", "gòong".

##### Version 1.0.10: (26/02/2019)
- Sửa lỗi "duocd".

##### Version 1.0.9: (22/02/2019)
- Sửa lỗi từ sai khi đổi chế độ mà không bấm phím Space.

##### Version 1.0.8: (19/02/2019)
- Phím chuyển: Control + Command + Space  --> Control + Z

##### Version 1.0.7: (15/02/2019)
- Sửa lỗi "duongd".
- Sửa lỗi phụ âm cuối "t".

##### Version 1.0.6: (15/02/2019)
- Sửa lỗi "quatw".

##### Version 1.0.5: (13/02/2019)
- Nâng cao chính tả.
- Sửa icon cho màn hình non-retina.

##### Version 1.0.3: (11/02/2019)
- Sửa lỗi thanh địa chỉ trên Chrome.

##### Version 1.0: (11/02/2019)
- Phát hành lần đầu.