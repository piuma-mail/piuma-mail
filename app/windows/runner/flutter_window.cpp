#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "window_place.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  // Still hidden: back where it was last time.
  maximized_ = RestoreWindowPlace(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  shell_ = std::make_unique<Shell>(flutter_controller_->engine()->messenger(),
                                   GetHandle());
  unread_badge_ = std::make_unique<UnreadBadge>(
      flutter_controller_->engine()->messenger(), GetHandle());
  // A message opened in a window of its own gets the plugins too.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      if (maximized_) {
        ::ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
      } else {
        this->Show();
      }
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  shell_ = nullptr;
  unread_badge_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Signing out, restarting or shutting down: Windows may end the process
  // as soon as this returns, before Dart hears anything. A normal end,
  // not a crash for the next start to report. Seen before Flutter, which
  // could answer it first.
  if (message == WM_ENDSESSION && wparam == TRUE && shell_) {
    shell_->EndSession();
  }

  // Where the window is, for the next launch: after a move or a resize,
  // on maximizing or restoring, and before it closes or the session ends.
  switch (message) {
    case WM_ENTERSIZEMOVE:
      sizing_ = true;
      break;
    case WM_EXITSIZEMOVE:
      sizing_ = false;
      SaveWindowPlace(hwnd);
      break;
    case WM_SIZE:
      if (!sizing_ && (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED)) {
        SaveWindowPlace(hwnd);
      }
      break;
    case WM_CLOSE:
    case WM_QUERYENDSESSION:
      SaveWindowPlace(hwnd);
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (shell_) {
    if (auto handled = shell_->HandleMessage(hwnd, message, wparam, lparam)) {
      return *handled;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      // A later launch handed over its command line (see main.cpp): a
      // mailto: link, an .eml file, files to send. Untrusted: Dart
      // checks every word (lib/outside/arrivals.dart).
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == kForwardedCommandLine &&
          data->lpData != nullptr && data->cbData >= sizeof(wchar_t) &&
          data->cbData % sizeof(wchar_t) == 0) {
        const auto* text = static_cast<const wchar_t*>(data->lpData);
        std::wstring line(text, data->cbData / sizeof(wchar_t));
        // Up to the first NUL, whatever the sender said its size was.
        line.resize(wcsnlen(line.c_str(), line.size()));
        if (shell_) shell_->Forward(line);
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
