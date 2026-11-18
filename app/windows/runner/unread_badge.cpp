#include "unread_badge.h"

#include <flutter/standard_method_codec.h>
#include <shobjidl.h>

#include <string>

namespace {

std::wstring Widen(const std::string& text) {
  if (text.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), size);
  return out;
}

// A round badge with [text] in white on [argb], [size] pixels square.
HICON DrawBadge(const std::wstring& text, unsigned int argb, int size) {
  BITMAPV5HEADER header = {};
  header.bV5Size = sizeof(header);
  header.bV5Width = size;
  header.bV5Height = -size;
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;
  HDC screen = GetDC(nullptr);
  void* bits = nullptr;
  HBITMAP color = CreateDIBSection(screen, reinterpret_cast<BITMAPINFO*>(&header),
                                   DIB_RGB_COLORS, &bits, nullptr, 0);
  HDC dc = CreateCompatibleDC(screen);
  ReleaseDC(nullptr, screen);
  if (color == nullptr || dc == nullptr) {
    if (color) DeleteObject(color);
    if (dc) DeleteDC(dc);
    return nullptr;
  }
  HGDIOBJ old = SelectObject(dc, color);
  const COLORREF fill =
      RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
  HBRUSH brush = CreateSolidBrush(fill);
  HPEN pen = CreatePen(PS_SOLID, 1, fill);
  HGDIOBJ old_brush = SelectObject(dc, brush);
  HGDIOBJ old_pen = SelectObject(dc, pen);
  Ellipse(dc, 0, 0, size, size);
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);
  HFONT font = CreateFontW(-(size * (text.size() > 2 ? 9 : 11) / 16), 0, 0, 0,
                           FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  HGDIOBJ old_font = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(255, 255, 255));
  RECT box = {0, 0, size, size};
  DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &box,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  SelectObject(dc, old_font);
  DeleteObject(font);
  GdiFlush();
  // GDI leaves alpha at 0: what was drawn is opaque, the rest clear.
  auto* pixels = static_cast<unsigned int*>(bits);
  for (int i = 0; i < size * size; i++) {
    if (pixels[i] & 0x00FFFFFF) pixels[i] |= 0xFF000000;
  }
  SelectObject(dc, old);
  DeleteDC(dc);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(color);
  DeleteObject(mask);
  return icon;
}

}  // namespace

UnreadBadge::UnreadBadge(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "piuma/badge",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "set") {
          result->NotImplemented();
          return;
        }
        int count = 0;
        std::wstring label;
        unsigned int color = 0xFF3451D1;
        if (const auto* args =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto find = [args](const char* key) -> const flutter::EncodableValue* {
            auto it = args->find(flutter::EncodableValue(key));
            return it == args->end() ? nullptr : &it->second;
          };
          if (auto* v = find("count")) {
            if (auto* n = std::get_if<int32_t>(v)) count = *n;
            if (auto* n = std::get_if<int64_t>(v)) count = static_cast<int>(*n);
          }
          if (auto* v = find("label")) {
            if (auto* s = std::get_if<std::string>(v)) label = Widen(*s);
          }
          if (auto* v = find("color")) {
            if (auto* n = std::get_if<int32_t>(v)) color = static_cast<unsigned int>(*n);
            if (auto* n = std::get_if<int64_t>(v)) color = static_cast<unsigned int>(*n);
          }
        }
        Set(count, label, color);
        result->Success();
      });
}

UnreadBadge::~UnreadBadge() {
  if (icon_) DestroyIcon(icon_);
}

void UnreadBadge::Set(int count, const std::wstring& label,
                      unsigned int color) {
  ITaskbarList3* taskbar = nullptr;
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&taskbar)))) {
    return;
  }
  HICON next = nullptr;
  if (count > 0) {
    const UINT dpi = GetDpiForWindow(window_);
    const int size = MulDiv(16, dpi == 0 ? 96 : dpi, 96);
    next = DrawBadge(count > 99 ? L"99+" : std::to_wstring(count), color, size);
  }
  if (SUCCEEDED(taskbar->HrInit())) {
    taskbar->SetOverlayIcon(window_, next, next ? label.c_str() : L"");
  }
  taskbar->Release();
  if (icon_) DestroyIcon(icon_);
  icon_ = next;
}
