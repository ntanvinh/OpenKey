//
//  AIText.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AIText.h"

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

std::wstring forError(const vai::Error& error, const vai::Config& config) {
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
