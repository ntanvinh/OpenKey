//
//  AIText.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AIText.h"
#include "../../../engine/AIAgent.h"

namespace AIText {

std::wstring forAddressProblem(vai::AddressProblem problem) {
    switch (problem) {
    case vai::AddressProblem::None: return L"";
    case vai::AddressProblem::Empty: return L"Chưa nhập địa chỉ máy chủ.";
    case vai::AddressProblem::Invalid: return L"Địa chỉ không hợp lệ. Ví dụ: https://api.openai.com/v1";
    case vai::AddressProblem::HasCredentials:
        return L"Địa chỉ không được chứa tên người dùng hay mật khẩu. Hãy nhập key ở ô API key.";
    case vai::AddressProblem::HasQueryOrFragment: return L"Địa chỉ không được có dấu ? hay #. Chỉ nhập đến phần /v1.";
    case vai::AddressProblem::InsecureRemote:
        return L"Địa chỉ ngoài internet phải dùng https để key và nội dung không bị lộ. Chỉ máy chạy cục bộ hoặc trong mạng nội bộ mới được dùng http.";
    case vai::AddressProblem::BadScheme: return L"Địa chỉ phải bắt đầu bằng https:// (hoặc http:// cho máy trong mạng nội bộ).";
    }
    return L"";
}

std::wstring forKeyProblem(vai::KeyProblem problem) {
    switch (problem) {
    case vai::KeyProblem::None: return L"";
    case vai::KeyProblem::Empty: return L"Chưa nhập key.";
    case vai::KeyProblem::BadCharacters: return L"Key có khoảng trắng hoặc ký tự lạ ở giữa. Hãy sao chép lại cả key, không thêm gì khác.";
    case vai::KeyProblem::TooLong: return L"Key dài bất thường. Hãy kiểm tra lại.";
    }
    return L"";
}

static std::wstring detailOf(const vai::Error& error) {
    return error.detail.empty() ? L"" : L" (" + utf8ToWideString(error.detail) + L")";
}

//What went wrong with a program of the computer (Codex CLI, Claude Code CLI, Antigravity CLI), see engine/AIAgent.h
static std::wstring forAgentError(const vai::Error& error, const vai::Config& config, const vai::agent::Agent& program) {
    std::wstring name = utf8ToWideString(program.displayName);
    std::wstring command = utf8ToWideString(program.command);
    std::wstring detail = detailOf(error);
    switch (error.code) {
    case vai::ErrorCode::None: return L"";
    case vai::ErrorCode::NoProgram: {
        if (error.detail == "script")
            return name + L" là một tệp script (.cmd) nên không nhận được chữ có ký tự đặc biệt hoặc nhiều dòng. "
                          L"Hãy bấm \"Chọn...\" trong Cài đặt AI và chọn tệp .exe của chương trình.";
        std::wstring install = program.installHint.empty() ? std::wstring() : L" Cài bằng: " + utf8ToWideString(program.installHint) + L".";
        return L"Không chạy được chương trình \"" + command + L"\"" + detail + L"." + install +
               L" Hoặc bấm \"Chọn...\" trong Cài đặt AI để chỉ đường dẫn.";
    }
    case vai::ErrorCode::Login:
        return name + L" chưa đăng nhập, hoặc phiên đăng nhập đã hết hạn. Mở Command Prompt hoặc PowerShell, chạy `" +
               utf8ToWideString(program.loginHint) + L"` rồi thử lại." + detail;
    case vai::ErrorCode::Model:
        return name + L" không dùng được model \"" + (config.model.empty() ? std::wstring(L"đang chọn") : utf8ToWideString(config.model)) +
               L"\". Chọn model khác trong Cài đặt AI (nút \"Tải danh sách\")." + detail;
    case vai::ErrorCode::Effort:
        return name + L" không nhận mức suy nghĩ \"" + utf8ToWideString(config.effort) +
               L"\" cho model này. Chọn mức khác, hoặc \"Mặc định của chương trình\", trong Cài đặt AI." + detail;
    case vai::ErrorCode::OldProgram:
        return name + L" không nhận một tùy chọn mà VOpenKey AI dùng: bản của chương trình có thể quá cũ, hoặc đã đổi cách gọi. "
                      L"Cập nhật chương trình rồi thử lại." + detail;
    case vai::ErrorCode::RateLimit:
        return name + L" báo đã hết hạn mức hoặc bị giới hạn tốc độ. Thử lại sau, hoặc chọn model nhẹ hơn." + detail;
    case vai::ErrorCode::Network:
        return name + L" không kết nối được tới dịch vụ. Kiểm tra mạng rồi thử lại." + detail;
    case vai::ErrorCode::Timeout:
        return name + L" không trả lời sau 10 phút nên đã bị dừng. Thử mức suy nghĩ thấp hơn, hoặc model nhẹ hơn.";
    case vai::ErrorCode::TooMuch:
        if (error.detail == "arguments")
            return L"Chữ quá dài để gửi cho " + name + L" (chương trình này chỉ nhận chữ qua dòng lệnh, Windows giới hạn khoảng 30.000 ký tự). "
                   L"Hãy chọn đoạn ngắn hơn hoặc dùng Codex CLI / Claude Code CLI.";
        return name + L" trả về quá nhiều chữ nên đã bị dừng. Thử lại với yêu cầu ngắn hơn.";
    case vai::ErrorCode::NoPicture: {
        std::wstring said = error.detail.empty() ? std::wstring() : L" (" + name + L" nói: \"" + utf8ToWideString(error.detail) + L"\")";
        return name + L" không tạo ra ảnh nào. Thử mô tả khác, hoặc chọn model khác." + said;
    }
    case vai::ErrorCode::BadPicture:
        return L"Không đọc được ảnh mà " + name + L" đã tạo (" + utf8ToWideString(error.detail) + L").";
    case vai::ErrorCode::Cancelled: return L"Đã dừng.";
    case vai::ErrorCode::Empty: return name + L" không trả về nội dung nào. Thử lại, hoặc đổi model." + detail;
    case vai::ErrorCode::Server:
        if (!error.detail.empty())
            return name + L" báo lỗi: " + utf8ToWideString(error.detail);
        return name + L" dừng bất ngờ (mã " + std::to_wstring(error.status) + L") mà không nói lý do. Thử chạy `" + command +
               L"` trong Command Prompt để xem.";
    default:
        return name + L" báo lỗi." + detail;
    }
}

std::wstring forError(const vai::Error& error, const vai::Config& config) {
    const vai::agent::Agent* program = vai::agent::find(config.provider.id);
    if (program != NULL)
        return forAgentError(error, config, *program);
    std::wstring name = displayName(config.provider);
    std::wstring model = utf8ToWideString(config.model);
    switch (error.code) {
    case vai::ErrorCode::None: return L"";
    case vai::ErrorCode::NoKey:
        return L"Chưa có API key của " + name + L" cho tài khoản Windows này. Vào Cài đặt AI để nhập.";
    case vai::ErrorCode::BadAddress: return forAddressProblem(vai::AddressProblem::Invalid);
    case vai::ErrorCode::BadKey: return forKeyProblem(vai::KeyProblem::BadCharacters);
    case vai::ErrorCode::Authentication:
        return name + L" không chấp nhận key này, hoặc key không có quyền dùng model \"" + model + L"\". Kiểm tra lại key trong Cài đặt AI." +
               detailOf(error);
    case vai::ErrorCode::RateLimit:
        return L"Đã vượt giới hạn yêu cầu hoặc hết hạn mức của " + name + L". Thử lại sau, hoặc kiểm tra gói sử dụng." + detailOf(error);
    case vai::ErrorCode::Model:
        return L"Không tìm thấy model \"" + model + L"\" hoặc địa chỉ máy chủ sai. Dùng nút \"Tải danh sách\" trong Cài đặt AI để chọn model." +
               detailOf(error);
    case vai::ErrorCode::Server:
        if (error.status >= 300 && error.status < 400)
            return L"Máy chủ chuyển hướng sang địa chỉ khác nên VOpenKey AI dừng lại để không gửi key đi nơi khác. Hãy sửa địa chỉ máy chủ trong Cài đặt AI.";
        if (error.status >= 500)
            return L"Máy chủ AI đang gặp sự cố (mã " + std::to_wstring(error.status) + L"). Thử lại sau." + detailOf(error);
        if (error.status > 0)
            return L"Máy chủ từ chối yêu cầu (mã " + std::to_wstring(error.status) + L")." + detailOf(error);
        return L"AI báo lỗi: " + utf8ToWideString(error.detail);
    case vai::ErrorCode::Network: return utf8ToWideString(error.detail);
    case vai::ErrorCode::Cancelled: return L"Đã dừng.";
    case vai::ErrorCode::Empty: return L"AI không trả về nội dung nào. Thử lại, hoặc đổi model.";
    case vai::ErrorCode::Rejected:
        return name + L" từ chối yêu cầu này (" + utf8ToWideString(error.detail) + L").";
    default: //the codes of the programs of the computer only come with those (forAgentError)
        break;
    }
    return L"";
}

std::wstring noteForProvider(const std::string& id) {
    if (id == "qwen")
        return L"Địa chỉ mặc định là máy chủ quốc tế. Tài khoản ở Trung Quốc dùng dashscope.aliyuncs.com.";
    if (id == "openrouter")
        return L"Một key dùng được nhiều AI. Tên model có dạng nhà-cung-cấp/tên-model.";
    if (id == "ollama")
        return L"Chạy trên máy này, không cần key. Cài Ollama từ ollama.com, chạy `ollama serve` rồi tải model bằng `ollama pull llama3.2`.";
    if (id == "lmstudio")
        return L"Chạy trên máy này, không cần key. Bật Local Server trong LM Studio.";
    if (id == "custom")
        return L"Cho llama.cpp, vLLM, LocalAI hoặc dịch vụ khác. Địa chỉ dạng https://máy-chủ/v1. Key để trống nếu máy chủ không đòi.";
    //programs of the computer: signed in by themselves, so no key; run in an empty folder with nothing but text allowed
    if (id == "codex-cli")
        return L"Dùng Codex CLI đã đăng nhập sẵn trên máy (`codex login`), không cần API key. Chương trình chạy trong thư mục tạm trống, không có công cụ, "
               L"không ghi tệp, không lưu phiên; chữ của bạn đi vào đầu vào chuẩn của nó. Nút \"Tạo ảnh\" của trợ lý AI dùng kỹ năng $imagegen của Codex. "
               L"Cài: npm install -g @openai/codex.";
    if (id == "claude-cli")
        return L"Dùng Claude Code CLI đã đăng nhập sẵn trên máy (`claude auth login`), không cần API key. Chương trình chạy ở chế độ chỉ viết chữ, "
               L"trong thư mục tạm trống, không lưu phiên. Nên chọn tệp claude.exe (bản cài của Anthropic); bản npm là script .cmd, không nhận được "
               L"hướng dẫn nhiều dòng.";
    if (id == "agy-cli")
        return L"Dùng Antigravity CLI đã đăng nhập sẵn trên máy, không cần API key. Chương trình chỉ nhận chữ qua dòng lệnh nên cần là tệp .exe, "
               L"và Windows giới hạn khoảng 30.000 ký tự. Lưu ý: Antigravity CLI tự lưu mỗi lần hỏi thành một cuộc trò chuyện trong thư mục của nó; "
               L"VOpenKey AI không xóa được.";
    return L"";
}

std::wstring displayName(const vai::Provider& provider) {
    const std::string& id = provider.id;
    if (id == "ollama") return L"Ollama (chạy trên máy)";
    if (id == "lmstudio") return L"LM Studio (chạy trên máy)";
    if (id == "custom") return L"Khác (tương thích OpenAI)";
    return utf8ToWideString(provider.name);
}

} // namespace AIText
