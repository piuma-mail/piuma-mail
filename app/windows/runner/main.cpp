#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
// After windows.h, which it needs.
#include <shellapi.h>
#include <string.h>

#include <cwctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "mail_handler.h"
#include "start_menu.h"
#include "utils.h"

namespace {

// Whether [word] starts with a URI scheme (mailto:, file:): letters,
// digits, "+", "-" or "." before a ":", two characters at least, so
// "C:\..." stays a drive.
bool HasScheme(const std::wstring& word) {
  size_t colon = word.find(L':');
  if (colon == std::wstring::npos || colon < 2 || !std::iswalpha(word[0])) {
    return false;
  }
  for (size_t i = 1; i < colon; i++) {
    wchar_t c = word[i];
    if (!std::iswalnum(c) && c != L'+' && c != L'-' && c != L'.') {
      return false;
    }
  }
  return true;
}

// [word] quoted so that CommandLineToArgvW reads it back as it is.
std::wstring Quoted(const std::wstring& word) {
  std::wstring out = L"\"";
  size_t slashes = 0;
  for (wchar_t c : word) {
    if (c == L'\\') {
      slashes++;
      continue;
    }
    // Backslashes before a quote are doubled, and the quote escaped.
    out.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
    slashes = 0;
    out.push_back(c);
  }
  // Before the closing quote, too.
  out.append(slashes * 2, L'\\');
  out.push_back(L'"');
  return out;
}

// This launch's command line with every relative path made whole
// against this launch's folder: the running Piuma has its own, and would
// look for the file there. Flags, URIs and absolute paths stay as they
// are; Dart checks every word (lib/outside/arrivals.dart).
std::wstring Resolved(const wchar_t* command_line) {
  std::wstring line = command_line != nullptr ? command_line : L"";
  if (line.empty()) return line;
  int argc = 0;
  // The first word is read as the program: a stand-in goes first.
  const std::wstring full = L"piuma " + line;
  wchar_t** argv = ::CommandLineToArgvW(full.c_str(), &argc);
  if (argv == nullptr) return line;
  std::wstring out;
  for (int i = 1; i < argc; i++) {
    std::wstring word = argv[i];
    if (!word.empty() && word[0] != L'-' && !HasScheme(word) &&
        word != L"multi_window") {
      DWORD n = ::GetFullPathNameW(word.c_str(), 0, nullptr, nullptr);
      if (n > 0 && n < 32768) {
        std::vector<wchar_t> buffer(n);
        DWORD got =
            ::GetFullPathNameW(word.c_str(), n, buffer.data(), nullptr);
        if (got > 0 && got < n) word.assign(buffer.data(), got);
      }
    }
    if (!out.empty()) out.push_back(L' ');
    out += Quoted(word);
  }
  ::LocalFree(argv);
  return out;
}

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
  std::wstring line = Resolved(command_line);
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
  // The installer's hooks (Velopack) register Piuma as a mail app, or
  // remove it, and end: never a window, never handed to a running Piuma.
  if (HandleInstallerHook(command_line)) {
    return EXIT_SUCCESS;
  }
  // One Piuma per person and session: two would both sync, notify and
  // send the outbox on one database (the outbox's claims keep a message
  // from going twice, but not the rest). Launched again, the open window
  // comes forward with the new command line (a mailto: link, a file).
  const wchar_t* title = IsDevCopy() ? L"Piuma Mail (dev)" : L"Piuma Mail";
  // Started at sign-in: only the tray until the person opens it.
  // Never with a mailto: link: a link opens with "%1", and one written to
  // break out of its quotes could add the flag (Dart, too, takes only the
  // link then).
  bool background = false;
  bool link = false;
  for (const auto& argument : GetCommandLineArguments()) {
    if (argument == "--background") background = true;
    if (_strnicmp(argument.c_str(), "mailto:", 7) == 0) link = true;
  }
  if (link) background = false;
  HANDLE single = ::CreateMutex(
      nullptr, TRUE,
      IsDevCopy() ? L"Local\\PiumaMail.Dev" : L"Local\\PiumaMail");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (background) {
      // Already running: signing in has nothing to bring forward.
      ::CloseHandle(single);
      return EXIT_SUCCESS;
    }
    // Another Piuma holds it. Hand over to its window as soon as it has
    // one (it may be starting), looking every 100 ms without waiting on
    // the mutex. Should its owner end meanwhile (an update restarts into
    // itself), the mutex comes to this launch, which goes on as the one.
    bool ours = false;
    for (int i = 0; i < 50 && !ours; i++) {
      if (HandToRunning(title, command_line)) {
        ::CloseHandle(single);
        return EXIT_SUCCESS;
      }
      DWORD free = ::WaitForSingleObject(single, 0);
      ours = free == WAIT_OBJECT_0 || free == WAIT_ABANDONED;
      if (!ours) {
        ::Sleep(100);
      }
    }
    if (!ours) {
      // Alive and still without a window: never a second Piuma on the
      // same data. This launch ends; the person can launch again.
      ::CloseHandle(single);
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

  FlutterWindow window(project, background);
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
