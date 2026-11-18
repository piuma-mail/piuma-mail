#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>
#include <vector>

#include "unread_badge.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // WM_COPYDATA tag of a later launch's command line (see main.cpp).
  static constexpr ULONG_PTR kForwardedCommandLine = 0x5049554D;  // "PIUM"

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The unread count on the taskbar button.
  std::unique_ptr<UnreadBadge> unread_badge_;
  // Command lines of later launches, oldest first, for what will read
  // them (a mailto: handler).
  std::vector<std::wstring> forwarded_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
