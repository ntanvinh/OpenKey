# VOpenKey AI — Privacy Policy

*English first, Tiếng Việt bên dưới.*

Effective date: 22 October 2026 · Developer: LSSoft · Contact: <https://lssoft.io.vn/en/contact>

## English

**In short.** VOpenKey AI turns your keystrokes into Vietnamese on your own computer. It has no account, no ads and no analytics, and it does not send what you type anywhere. Text leaves your computer only when you use the optional AI assistant (and then only what you send it, to the service you chose), when the app checks for or downloads an update, or when you start an optional download yourself.

### What the app reads

- **Keystrokes.** To type Vietnamese the app watches keyboard events (macOS: the Accessibility and Input Monitoring permissions; Windows: a keyboard hook). They are handled in memory on your computer and are not sent anywhere. macOS hides keys typed in password fields from apps like this one.
- **Text near the cursor and the selected text.** On macOS the app reads the selection, and a few characters around the cursor, through Accessibility. It does this to place the suggestion bar, to show the case bar and, when you open the AI assistant, to fill its box. Nothing is stored or sent by this alone. The AI assistant never reads a password field.
- **Clipboard.** When Accessibility cannot give the selection, the assistant presses ⌘C, reads the clipboard and puts your previous clipboard back. Inserting a snippet and the case bar also use the clipboard briefly and restore it.

### What is stored on your computer

- **Settings and abbreviations** (macOS: the app's preferences; Windows: the registry key `HKCU\SOFTWARE\TuyenMai\OpenKey`).
- **Words you have learned** (macOS, setting *Học từ cách gõ của bạn*, on by default): `~/Library/Application Support/VOpenKey/learned.txt` keeps lowercase words and short word sequences you type, with how often, only on this Mac, readable only by you. Terminal apps are left out by default. *Settings → Dữ liệu đã học → Xóa…* forgets everything; you can also delete the file.
- **API keys you enter for the AI assistant:** in the macOS Keychain of this Mac, never in a file.
- **Updates:** a downloaded update waits in `~/Library/Application Support/VOpenKey/Updates` until you restart the app.
- **A diagnostics log** (`~/Library/Logs/VOpenKey/diagnostics.log`) exists only in developer builds. Release builds keep it off. It records counts and app identifiers, never what you typed.

### The AI assistant (macOS, optional)

It runs only when you press its shortcut and then send a request. What is sent is the text in its box: the selected text you started from plus your instruction. When you press one of its ready-made conversions (Fix mistakes, Polite, Translate to English…) a fixed sentence that says what to do is sent in front of that text; nothing else is added. Where it goes depends on the provider you pick in Settings:

- **A cloud service** (OpenAI, Google Gemini, Anthropic, DeepSeek, Alibaba Cloud Model Studio, OpenRouter, or an address you type), with an API key you provide. The key is sent only to that service, as a request header, and is kept in your Keychain, not synced to other devices. That service handles your text under its own terms and privacy policy.
- **A server on your own computer** (Ollama, LM Studio): the text stays on your computer.
- **An AI tool you already use** (Codex, Claude Code, Antigravity): the app starts it on your computer in an empty temporary folder and gives it the text. The tool sends it to its own company under your account with them; the app never sees that account.

The assistant's box is cleared when you close it. LSSoft has no server for this feature and receives none of it.

### Other network use

- **Update check (macOS, on by default, can be turned off in Settings).** At launch and every 6 hours the app asks GitHub for the newest release of the project (`api.github.com`, and `github.com` as a fallback). GitHub sees what any web request shows, such as your IP address; the app adds no identifier and sends none of your text. The app downloads a new version from the project's GitHub release by itself unless you turn automatic installation off, and installs it only if it is signed with the developer's own Developer ID certificate.
- **Update check (Windows, off by default).** If you turn it on, the app reads `version.json` from the project's GitHub repository, and downloads the new version from its GitHub release only when you confirm.
- **Local AI setup (macOS, only when you press the button).** The app downloads the Ollama installer from GitHub; Ollama then downloads the model you choose from its own registry.
- **Donate window (macOS and Windows).** The QR code is made on your computer (on Windows it is a picture inside the program) and the app sends nothing when it shows it. "Mở PayPal" opens the project's PayPal page in your browser. "Tôi đã ủng hộ" is only a setting on this computer that hides the Donate menu item; the app does not check any payment and tells nobody.
- Links you click (the releases page, a provider's API-key page, the About links) open in your browser.

### What we do not do

We do not collect your typing, show ads, use analytics or crash-reporting services, sell data, or ask you to create an account. The app is open source (GPL-3.0), so you can check all of this in the code.

### Children

The app is a keyboard tool for everyone and is not directed at children. LSSoft collects no personal data from anyone through it.

### Changes and contact

If the app changes how it handles data, this page is updated with a new date. Questions: <https://lssoft.io.vn/en/contact>.

---

## Tiếng Việt

**Tóm tắt.** VOpenKey AI biến phím bạn gõ thành tiếng Việt ngay trên máy của bạn. App không có tài khoản, không quảng cáo, không phân tích dữ liệu và không gửi nội dung bạn gõ đi đâu cả. Chữ chỉ rời khỏi máy khi bạn dùng trợ lý AI (tùy chọn; chỉ gửi đúng nội dung bạn đưa vào, tới dịch vụ bạn chọn), khi app kiểm tra hoặc tải bản cập nhật, hoặc khi chính bạn bấm một nút tải về.

### App đọc những gì

- **Phím bạn gõ.** Để gõ tiếng Việt, app theo dõi sự kiện bàn phím (macOS: quyền Trợ năng và Giám sát đầu vào; Windows: một hook bàn phím). Chúng chỉ được xử lý trong bộ nhớ trên máy bạn và không được gửi đi. macOS giấu các phím gõ trong ô mật khẩu khỏi những app như thế này.
- **Chữ gần con trỏ và chữ đang chọn.** Trên macOS, app đọc phần chữ đang chọn và vài ký tự quanh con trỏ qua Trợ năng, để đặt thanh gợi ý, hiện thanh đổi chữ hoa/thường và điền sẵn vào hộp của trợ lý AI khi bạn mở nó. Riêng việc đọc này không lưu và không gửi gì. Trợ lý AI không bao giờ đọc ô mật khẩu.
- **Bộ nhớ tạm (clipboard).** Khi Trợ năng không cho lấy được phần chọn, trợ lý nhấn ⌘C, đọc clipboard rồi trả lại nội dung clipboard cũ của bạn. Việc chèn snippet và thanh đổi chữ hoa/thường cũng dùng clipboard trong chốc lát rồi khôi phục.

### Dữ liệu lưu trên máy bạn

- **Cài đặt và gõ tắt** (macOS: tùy chọn của app; Windows: khóa registry `HKCU\SOFTWARE\TuyenMai\OpenKey`).
- **Từ đã học** (macOS, mục *Học từ cách gõ của bạn*, bật sẵn): `~/Library/Application Support/VOpenKey/learned.txt` lưu các từ và cụm từ ngắn bạn hay gõ (chữ thường) kèm số lần, chỉ trên máy này và chỉ bạn đọc được. Các ứng dụng Terminal mặc định bị bỏ qua. *Cài đặt → Dữ liệu đã học → Xóa…* sẽ quên toàn bộ; bạn cũng có thể xóa thẳng file này.
- **API key bạn nhập cho trợ lý AI:** nằm trong Keychain của máy này, không bao giờ ở trong file.
- **Bản cập nhật:** bản tải về nằm ở `~/Library/Application Support/VOpenKey/Updates` cho tới khi bạn khởi động lại app.
- **Nhật ký chẩn đoán** (`~/Library/Logs/VOpenKey/diagnostics.log`) chỉ có trong bản dành cho lập trình viên; bản phát hành để tắt. Nó chỉ ghi số đếm và mã định danh ứng dụng, không bao giờ ghi nội dung bạn gõ.

### Trợ lý AI (macOS, tùy chọn)

Trợ lý chỉ chạy khi bạn nhấn phím tắt rồi gửi yêu cầu. Nội dung gửi đi là chữ trong hộp của nó: phần chữ bạn chọn lúc bắt đầu cộng với yêu cầu của bạn. Khi bạn bấm một kiểu chuyển đổi có sẵn (Sửa lỗi, Lịch sự, Dịch sang Anh…), một câu cố định nói rõ việc cần làm được gửi kèm ngay trước chữ đó; không thêm gì khác. Nơi nhận phụ thuộc nhà cung cấp bạn chọn trong Cài đặt:

- **Dịch vụ đám mây** (OpenAI, Google Gemini, Anthropic, DeepSeek, Alibaba Cloud Model Studio, OpenRouter, hoặc địa chỉ bạn tự nhập), dùng API key của bạn. Key chỉ được gửi tới đúng dịch vụ đó, trong phần đầu của yêu cầu, và nằm trong Keychain, không đồng bộ sang thiết bị khác. Dịch vụ đó xử lý chữ của bạn theo điều khoản và chính sách riêng tư của chính họ.
- **Máy chủ ngay trên máy bạn** (Ollama, LM Studio): chữ không rời khỏi máy.
- **Công cụ AI bạn đã dùng sẵn** (Codex, Claude Code, Antigravity): app khởi chạy công cụ đó trên máy bạn, trong một thư mục tạm trống, và đưa chữ cho nó. Công cụ gửi chữ tới công ty của nó theo tài khoản bạn đăng nhập ở đó; app không bao giờ thấy tài khoản ấy.

Hộp của trợ lý được xóa sạch khi bạn đóng nó. LSSoft không có máy chủ nào cho tính năng này và không nhận được gì từ nó.

### Các kết nối mạng khác

- **Kiểm tra bản mới (macOS, bật sẵn, tắt được trong Cài đặt).** Khi mở app và cứ 6 giờ một lần, app hỏi GitHub về bản phát hành mới nhất của dự án (`api.github.com`, dự phòng là `github.com`). GitHub thấy những gì mọi yêu cầu web đều để lộ, như địa chỉ IP của bạn; app không thêm mã định danh nào và không gửi chữ của bạn. App tự tải bản mới từ GitHub Releases của dự án trừ khi bạn tắt cài đặt tự động, và chỉ cài khi bản đó được ký bằng chính chứng chỉ Developer ID của nhà phát triển.
- **Kiểm tra bản mới (Windows, tắt sẵn).** Nếu bạn bật, app đọc `version.json` từ kho GitHub của dự án, và chỉ tải bản mới từ GitHub Releases khi bạn đồng ý.
- **Cài AI chạy trên máy (macOS, chỉ khi bạn bấm nút).** App tải trình cài Ollama từ GitHub; sau đó Ollama tự tải mô hình bạn chọn từ kho của nó.
- **Cửa sổ Ủng hộ (macOS và Windows).** Mã QR được tạo ngay trên máy bạn (trên Windows là một hình nằm sẵn trong chương trình) và app không gửi gì khi hiện nó. "Mở PayPal" mở trang PayPal của dự án trong trình duyệt. "Tôi đã ủng hộ" chỉ là một tùy chọn trên máy tính này để ẩn mục Ủng hộ khỏi menu; app không kiểm tra giao dịch nào và không báo cho ai.
- Các liên kết bạn bấm (trang phát hành, trang lấy API key của nhà cung cấp, liên kết trong mục Giới thiệu) mở trong trình duyệt.

### Những điều chúng tôi không làm

Chúng tôi không thu thập nội dung bạn gõ, không hiện quảng cáo, không dùng dịch vụ phân tích hay báo lỗi, không bán dữ liệu và không bắt bạn tạo tài khoản. App là mã nguồn mở (GPL-3.0) nên bạn có thể tự kiểm tra tất cả những điều trên trong mã.

### Trẻ em

App là công cụ bàn phím cho mọi người, không hướng tới trẻ em. LSSoft không thu thập dữ liệu cá nhân của ai qua app này.

### Thay đổi và liên hệ

Nếu app đổi cách xử lý dữ liệu, trang này sẽ được cập nhật kèm ngày mới. Thắc mắc: <https://lssoft.io.vn/vi/contact>.
