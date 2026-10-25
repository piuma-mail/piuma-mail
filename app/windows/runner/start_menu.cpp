#include "start_menu.h"

#include <windows.h>

#include <knownfolders.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>

using Microsoft::WRL::ComPtr;

namespace {

std::wstring ExecutablePath() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  return std::wstring(path, length);
}

// The same id the notices are sent with (lib/notify/notifier.dart).
const wchar_t* AppId() {
  return IsDevCopy() ? L"Piuma.PiumaMail.Dev" : L"Piuma.PiumaMail";
}

std::wstring ShortcutPath() {
  PWSTR programs = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr,
                                    &programs))) {
    return L"";
  }
  std::wstring path = std::wstring(programs) +
                      (IsDevCopy() ? L"\\Piuma Mail (dev).lnk"
                                   : L"\\Piuma Mail.lnk");
  ::CoTaskMemFree(programs);
  return path;
}

// True when the shortcut is there, opens this program and carries the id.
bool ShortcutCurrent(const std::wstring& shortcut, const std::wstring& exe) {
  ComPtr<IShellLinkW> link;
  ComPtr<IPersistFile> file;
  ComPtr<IPropertyStore> store;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))) ||
      FAILED(link.As(&file)) || FAILED(file->Load(shortcut.c_str(), STGM_READ)) ||
      FAILED(link.As(&store))) {
    return false;
  }
  wchar_t target[MAX_PATH];
  if (FAILED(link->GetPath(target, MAX_PATH, nullptr, 0)) ||
      _wcsicmp(target, exe.c_str()) != 0) {
    return false;
  }
  PROPVARIANT id;
  if (FAILED(store->GetValue(PKEY_AppUserModel_ID, &id))) return false;
  const bool same = id.vt == VT_LPWSTR && wcscmp(id.pwszVal, AppId()) == 0;
  ::PropVariantClear(&id);
  return same;
}

}  // namespace

bool IsDevCopy() {
  // The installer keeps Update.exe one folder above the program
  // (...\PiumaMail\current\piuma_mail.exe).
  static const bool dev = [] {
    const std::wstring exe = ExecutablePath();
    const std::wstring dir = exe.substr(0, exe.find_last_of(L'\\'));
    const std::wstring root = dir.substr(0, dir.find_last_of(L'\\'));
    return ::GetFileAttributesW((root + L"\\Update.exe").c_str()) ==
           INVALID_FILE_ATTRIBUTES;
  }();
  return dev;
}

void RegisterStartMenu() {
  // The taskbar groups the windows under the same id.
  ::SetCurrentProcessExplicitAppUserModelID(AppId());

  const std::wstring shortcut = ShortcutPath();
  const std::wstring exe = ExecutablePath();
  if (shortcut.empty() || ShortcutCurrent(shortcut, exe)) return;

  ComPtr<IShellLinkW> link;
  ComPtr<IPropertyStore> store;
  ComPtr<IPersistFile> file;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))) ||
      FAILED(link->SetPath(exe.c_str())) || FAILED(link.As(&store))) {
    return;
  }
  const std::wstring dir = exe.substr(0, exe.find_last_of(L'\\'));
  link->SetWorkingDirectory(dir.c_str());
  PROPVARIANT id;
  if (FAILED(::InitPropVariantFromString(AppId(), &id))) return;
  const bool stored = SUCCEEDED(store->SetValue(PKEY_AppUserModel_ID, id)) &&
                      SUCCEEDED(store->Commit());
  ::PropVariantClear(&id);
  if (stored && SUCCEEDED(link.As(&file))) {
    file->Save(shortcut.c_str(), TRUE);
  }
}
