#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>
#include <vector>

#include "shell.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // With |start_hidden|, the window stays out of sight until the person
  // opens it from the tray (started at sign-in).
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
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

  // Later launches, the tray, closing to the tray (lib/outside/).
  std::unique_ptr<Shell> shell_;

  bool start_hidden_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
