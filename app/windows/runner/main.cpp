#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "start_menu.h"
#include "utils.h"

namespace {

// Hands a later launch's command line to the window already open, and
// brings it forward. True when there was one: this launch then ends.
bool HandToRunning(const wchar_t* title, const wchar_t* command_line) {
  HWND running = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title);
  if (running == nullptr) {
    return false;
  }
  ::ShowWindow(running, ::IsIconic(running) ? SW_RESTORE : SW_SHOW);
  // The launch just made by the person may bring it forward.
  ::SetForegroundWindow(running);
  std::wstring line = command_line != nullptr ? command_line : L"";
  COPYDATASTRUCT data{};
  data.dwData = FlutterWindow::kForwardedCommandLine;
  data.cbData = static_cast<DWORD>((line.size() + 1) * sizeof(wchar_t));
  data.lpData = line.data();
  DWORD_PTR ignored = 0;
  ::SendMessageTimeout(running, WM_COPYDATA, 0,
                       reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                       2000, &ignored);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One Piuma per person and session: two would both sync, notify and
  // send the outbox on one database (the outbox's claims keep a message
  // from going twice, but not the rest). Launched again, the open window
  // comes forward with the new command line (a mailto: link, one day).
  const wchar_t* title = IsDevCopy() ? L"Piuma Mail (dev)" : L"Piuma Mail";
  HANDLE single = ::CreateMutex(
      nullptr, TRUE,
      IsDevCopy() ? L"Local\\PiumaMail.Dev" : L"Local\\PiumaMail");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (HandToRunning(title, command_line)) {
      return EXIT_SUCCESS;
    }
    // Held, but no window yet or any more: one starting, or one ending
    // (an update restarts into itself). Wait for it a while.
    DWORD waited = ::WaitForSingleObject(single, 10000);
    if (waited == WAIT_TIMEOUT && HandToRunning(title, command_line)) {
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  RegisterStartMenu();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single != nullptr) {
    ::ReleaseMutex(single);
    ::CloseHandle(single);
  }
  return EXIT_SUCCESS;
}
