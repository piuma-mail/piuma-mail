#ifndef RUNNER_SHELL_H_
#define RUNNER_SHELL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

// The app's window and the rest of Windows (lib/outside/ in Dart, over
// the "piuma/shell" channel): later launches' command lines (a mailto:
// link, an .eml file), the tray icon while Piuma keeps running with its
// window closed, starting at sign-in, the default mail app, and the
// unread count in the tray's tooltip.
class Shell {
 public:
  Shell(flutter::BinaryMessenger* messenger, HWND window);
  ~Shell();

  // A later launch's command line (its arguments only), from main.cpp.
  void Forward(const std::wstring& command_line);

  // Window messages the shell answers: the tray, and closing the window
  // while Piuma keeps running. Empty for the rest.
  std::optional<LRESULT> HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam);

  // Removes the running session's marker: the app closed normally.
  void EndSession();

  // Message of the tray icon's clicks.
  static constexpr UINT kTrayMessage = WM_APP + 0x50;

 private:
  void Send(const std::vector<std::string>& args);
  void ShowTray(bool on);
  void ShowMenu(int x, int y);
  void Present();
  void Quit();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  // Dart listens: until then later launches wait here.
  bool ready_ = false;
  std::vector<std::vector<std::string>> waiting_;
  bool keep_running_ = false;
  bool tray_shown_ = false;
  bool quitting_ = false;
  std::wstring open_label_ = L"Open Piuma Mail";
  std::wstring compose_label_ = L"Compose";
  std::wstring quit_label_ = L"Quit";
  std::wstring tooltip_ = L"Piuma Mail";
  // The running session's marker (core/src/feedback.rs, session_marker).
  std::wstring session_marker_;
  // Explorer restarted: the tray icon is added again.
  UINT taskbar_created_ = 0;
};

#endif  // RUNNER_SHELL_H_
