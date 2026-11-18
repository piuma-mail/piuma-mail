#include "shell.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windowsx.h>

#include "mail_handler.h"
#include "resource.h"
#include "utils.h"

namespace {

constexpr UINT kTrayId = 1;
constexpr UINT kOpen = 1;
constexpr UINT kCompose = 2;
constexpr UINT kQuit = 3;

// Longest command line or label taken in.
constexpr size_t kMaxText = 512 * 1024;

std::wstring Widen(const std::string& text) {
  if (text.empty() || text.size() > kMaxText) return std::wstring();
  const int size = ::MultiByteToWideChar(
      CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        out.data(), size);
  return out;
}

const flutter::EncodableValue* Find(const flutter::EncodableValue* args,
                                    const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (map == nullptr) return nullptr;
  auto it = map->find(flutter::EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

bool FindBool(const flutter::EncodableValue* args, const char* key) {
  const auto* v = Find(args, key);
  const bool* b = v ? std::get_if<bool>(v) : nullptr;
  return b != nullptr && *b;
}

std::wstring FindText(const flutter::EncodableValue* args, const char* key,
                      const std::wstring& otherwise) {
  const auto* v = Find(args, key);
  const std::string* s = v ? std::get_if<std::string>(v) : nullptr;
  if (s == nullptr || s->empty()) return otherwise;
  return Widen(*s);
}

}  // namespace

Shell::Shell(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "piuma/shell", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        const flutter::EncodableValue* args = call.arguments();
        if (method == "ready") {
          ready_ = true;
          auto waiting = std::move(waiting_);
          waiting_.clear();
          for (const auto& line : waiting) Send(line);
          result->Success();
        } else if (method == "keepRunning") {
          keep_running_ = FindBool(args, "on");
          open_label_ = FindText(args, "open", open_label_);
          compose_label_ = FindText(args, "compose", compose_label_);
          quit_label_ = FindText(args, "quit", quit_label_);
          ShowTray(keep_running_);
          // Started hidden at sign-in but not to stay in the tray: the
          // window shows.
          if (!keep_running_ && !::IsWindowVisible(window_)) Present();
          result->Success();
        } else if (method == "startAtLogin") {
          SetStartAtLogin(FindBool(args, "on"));
          result->Success();
        } else if (method == "unread") {
          tooltip_ = FindText(args, "tooltip", L"Piuma Mail");
          if (tray_shown_) {
            NOTIFYICONDATAW data{};
            data.cbSize = sizeof(data);
            data.hWnd = window_;
            data.uID = kTrayId;
            data.uFlags = NIF_TIP | NIF_SHOWTIP;
            wcsncpy_s(data.szTip, tooltip_.c_str(), _TRUNCATE);
            ::Shell_NotifyIconW(NIM_MODIFY, &data);
          }
          result->Success();
        } else if (method == "defaultMail") {
          result->Success(flutter::EncodableValue(DefaultMailState()));
        } else if (method == "makeDefault") {
          OpenDefaultAppsSettings();
          // The person chooses in Settings; nothing is known yet.
          result->Success(flutter::EncodableValue("unknown"));
        } else if (method == "session") {
          // Only ever the marker the engine names (an absolute path to a
          // file called "running"), never another file to remove.
          const std::wstring marker = FindText(args, "marker", L"");
          const size_t slash = marker.find_last_of(L"\\/");
          if (marker.size() > 3 && slash != std::wstring::npos &&
              marker.compare(slash + 1, std::wstring::npos, L"running") == 0 &&
              (marker[1] == L':' || marker.rfind(L"\\\\", 0) == 0)) {
            session_marker_ = marker;
          }
          result->Success();
        } else if (method == "quit") {
          result->Success();
          Quit();
        } else {
          result->NotImplemented();
        }
      });
}

Shell::~Shell() { ShowTray(false); }

void Shell::Forward(const std::wstring& command_line) {
  if (command_line.size() > kMaxText) return;
  int argc = 0;
  // CommandLineToArgvW reads the first word as the program: a stand-in
  // goes first, so the arguments split the same way as at start.
  const std::wstring full = L"piuma " + command_line;
  wchar_t** argv = ::CommandLineToArgvW(full.c_str(), &argc);
  if (argv == nullptr) return;
  std::vector<std::string> args;
  for (int i = 1; i < argc && args.size() < 64; i++) {
    args.push_back(Utf8FromUtf16(argv[i]));
  }
  ::LocalFree(argv);
  if (args.empty()) return;
  if (!ready_) {
    if (waiting_.size() < 16) waiting_.push_back(std::move(args));
    return;
  }
  Send(args);
}

void Shell::Send(const std::vector<std::string>& args) {
  flutter::EncodableList list;
  for (const auto& a : args) list.emplace_back(a);
  channel_->InvokeMethod(
      "open", std::make_unique<flutter::EncodableValue>(std::move(list)));
}

void Shell::ShowTray(bool on) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  if (!on) {
    if (tray_shown_) ::Shell_NotifyIconW(NIM_DELETE, &data);
    tray_shown_ = false;
    return;
  }
  if (tray_shown_) return;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));
  wcsncpy_s(data.szTip, tooltip_.c_str(), _TRUNCATE);
  tray_shown_ = ::Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (tray_shown_) {
    // Keyboard and the newer click messages (NIN_SELECT, WM_CONTEXTMENU).
    data.uVersion = NOTIFYICON_VERSION_4;
    ::Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
  if (data.hIcon != nullptr) ::DestroyIcon(data.hIcon);
}

void Shell::ShowMenu(int x, int y) {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) return;
  ::AppendMenuW(menu, MF_STRING, kOpen, open_label_.c_str());
  ::AppendMenuW(menu, MF_STRING, kCompose, compose_label_.c_str());
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kQuit, quit_label_.c_str());
  ::SetMenuDefaultItem(menu, kOpen, FALSE);
  // Without this the menu stays open when the person clicks elsewhere.
  ::SetForegroundWindow(window_);
  const UINT picked = ::TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON |
                (::GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                           : TPM_LEFTALIGN),
      x, y, window_, nullptr);
  ::PostMessage(window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  switch (picked) {
    case kOpen:
      Present();
      break;
    case kCompose:
      Present();
      channel_->InvokeMethod("compose", nullptr);
      break;
    case kQuit:
      Quit();
      break;
  }
}

void Shell::Present() {
  ::ShowWindow(window_, ::IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(window_);
}

void Shell::EndSession() {
  if (!session_marker_.empty()) ::DeleteFileW(session_marker_.c_str());
}

void Shell::Quit() {
  if (quitting_) return;
  quitting_ = true;
  ShowTray(false);
  // Dart ends the session itself when it gets the exit request; told
  // here too, and the marker goes now, in case the close never gets
  // there (the window was already hidden in the tray).
  channel_->InvokeMethod("quitting", nullptr);
  EndSession();
  // Closed from the message loop, never from inside a callback of this
  // shell, which goes with the window.
  ::PostMessage(window_, WM_CLOSE, 0, 0);
}

std::optional<LRESULT> Shell::HandleMessage(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
        Present();
        return 0;
      case WM_CONTEXTMENU:
        ShowMenu(GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam));
        return 0;
    }
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    if (tray_shown_) {
      tray_shown_ = false;
      ShowTray(true);
    }
    return 0;
  }
  if (message == WM_CLOSE && keep_running_ && !quitting_) {
    // Out of sight, still syncing and notifying; the tray brings it back.
    ::ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  return std::nullopt;
}
