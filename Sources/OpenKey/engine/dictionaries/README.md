# Từ điển gợi ý

Các file ở đây được đóng gói vào app và dùng cho thanh gợi ý khi gõ. Định dạng file nằm ở đầu
[Suggest.h](../Suggest.h).

| File | Nội dung | Nguồn và giấy phép |
|---|---|---|
| `vi-base.txt` | Khoảng 500 từ thông dụng có số lần dùng, và khoảng 300 từ ghép phổ biến | Do dự án viết tay, GPL-3.0 như phần còn lại |
| `vi-wiktionary.txt` | Khoảng 5.000 âm tiết và 36.000 từ ghép | Tên các mục từ thuộc chuyên mục "Mục từ tiếng Việt" của [Wiktionary tiếng Việt](https://vi.wiktionary.org), giấy phép [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Chỉ lấy tên mục từ, không lấy định nghĩa. Tạo bằng `scripts/fetch-wiktionary-dictionary.py` |

`vi-wiktionary.txt` là dữ liệu riêng, không phải mã nguồn: nó giữ giấy phép CC BY-SA 4.0 và phải
giữ nguyên phần ghi nguồn ở đầu file. Muốn cập nhật, chạy lại script.

Wiktionary không có số lần dùng, mọi mục từ ghép đều có cùng một số nhỏ. Thứ tự gợi ý do
`vi-base.txt` (có số lần dùng thật) và những gì người dùng gõ quyết định.

Không đưa vào đây dữ liệu từ nguồn không rõ giấy phép (ví dụ bản scan từ điển còn bản quyền).
