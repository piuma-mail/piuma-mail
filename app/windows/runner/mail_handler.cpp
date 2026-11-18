#include "mail_handler.h"

#include <windows.h>

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include "start_menu.h"

using Microsoft::WRL::ComPtr;

namespace {

std::wstring ExecutablePath() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  return std::wstring(path, length);
}

// Names under which this copy registers; the dev copy (a build run from
// its folder) has its own, so it never touches an installed Piuma's.
struct Names {
  std::wstring app_name;     // As Default apps lists it.
  std::wstring app_key;      // Under HKCU\Software.
  std::wstring mailto_prog;  // ProgID of mailto: links.
  std::wstring eml_prog;     // ProgID of .eml files.
};

const Names& OurNames() {
  static const Names names = IsDevCopy()
                                 ? Names{L"Piuma Mail (dev)", L"PiumaMail.Dev",
                                         L"PiumaMail.Dev.mailto",
                                         L"PiumaMail.Dev.eml"}
                                 : Names{L"Piuma Mail", L"PiumaMail",
                                         L"PiumaMail.mailto", L"PiumaMail.eml"};
  return names;
}

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

bool SetString(const std::wstring& key, const wchar_t* name,
               const std::wstring& value) {
  return ::RegSetKeyValueW(
             HKEY_CURRENT_USER, key.c_str(), name, REG_SZ, value.c_str(),
             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

// A ProgID that opens this program with the link or file as its one
// argument.
void WriteProgId(const std::wstring& prog, const std::wstring& description,
                 bool url, const std::wstring& exe) {
  const std::wstring key = L"Software\\Classes\\" + prog;
  SetString(key, nullptr, description);
  if (url) {
    SetString(key, L"URL Protocol", L"");
  }
  SetString(key + L"\\DefaultIcon", nullptr, L"\"" + exe + L"\",0");
  SetString(key + L"\\shell\\open\\command", nullptr,
            L"\"" + exe + L"\" \"%1\"");
}

}  // namespace

void RegisterMailHandler() {
  const Names& n = OurNames();
  const std::wstring exe = ExecutablePath();
  WriteProgId(n.mailto_prog, L"URL:MailTo Protocol", true, exe);
  WriteProgId(n.eml_prog, L"Email message", false, exe);
  // Offered in "Open with" for .eml files, without taking the default.
  SetString(L"Software\\Classes\\.eml\\OpenWithProgids", n.eml_prog.c_str(),
            L"");

  const std::wstring caps = L"Software\\" + n.app_key + L"\\Capabilities";
  SetString(caps, L"ApplicationName", n.app_name);
  SetString(caps, L"ApplicationDescription", L"Mail, made light.");
  SetString(caps, L"ApplicationIcon", L"\"" + exe + L"\",0");
  SetString(caps + L"\\URLAssociations", L"mailto", n.mailto_prog);
  SetString(caps + L"\\FileAssociations", L".eml", n.eml_prog);
  SetString(L"Software\\RegisteredApplications", n.app_name.c_str(), caps);

  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

void UnregisterMailHandler() {
  const Names& n = OurNames();
  ::RegDeleteKeyValueW(HKEY_CURRENT_USER, L"Software\\RegisteredApplications",
                       n.app_name.c_str());
  ::RegDeleteTreeW(HKEY_CURRENT_USER, (L"Software\\" + n.app_key).c_str());
  ::RegDeleteTreeW(HKEY_CURRENT_USER,
                   (L"Software\\Classes\\" + n.mailto_prog).c_str());
  ::RegDeleteTreeW(HKEY_CURRENT_USER,
                   (L"Software\\Classes\\" + n.eml_prog).c_str());
  ::RegDeleteKeyValueW(HKEY_CURRENT_USER,
                       L"Software\\Classes\\.eml\\OpenWithProgids",
                       n.eml_prog.c_str());
  ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, n.app_name.c_str());
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

std::string DefaultMailState() {
  ComPtr<IApplicationAssociationRegistration> registration;
  if (FAILED(::CoCreateInstance(CLSID_ApplicationAssociationRegistration,
                                nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&registration)))) {
    return "unknown";
  }
  LPWSTR prog = nullptr;
  if (FAILED(registration->QueryCurrentDefault(L"mailto", AT_URLPROTOCOL,
                                               AL_EFFECTIVE, &prog)) ||
      prog == nullptr) {
    return "none";
  }
  const bool ours = _wcsicmp(prog, OurNames().mailto_prog.c_str()) == 0;
  ::CoTaskMemFree(prog);
  return ours ? "piuma" : "other";
}

void OpenDefaultAppsSettings() {
  RegisterMailHandler();
  // Straight to Piuma's own page of Default apps (Windows 11, and
  // Windows 10 since 2021); older ones open the list.
  std::wstring name = OurNames().app_name;
  std::wstring escaped;
  for (wchar_t c : name) {
    if (c == L' ') {
      escaped += L"%20";
    } else if (c == L'(') {
      escaped += L"%28";
    } else if (c == L')') {
      escaped += L"%29";
    } else {
      escaped += c;
    }
  }
  const std::wstring page =
      L"ms-settings:defaultapps?registeredAppUser=" + escaped;
  ::ShellExecuteW(nullptr, L"open", page.c_str(), nullptr, nullptr,
                  SW_SHOWNORMAL);
}

void SetStartAtLogin(bool on) {
  const wchar_t* name = OurNames().app_name.c_str();
  if (on) {
    SetString(kRunKey, name, L"\"" + ExecutablePath() + L"\" --background");
  } else {
    ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, name);
  }
}

bool HandleInstallerHook(const wchar_t* command_line) {
  if (command_line == nullptr) {
    return false;
  }
  int argc = 0;
  // The first word of a full command line is the program; this one is
  // only the arguments, so a stand-in goes first.
  const std::wstring full = std::wstring(L"piuma ") + command_line;
  wchar_t** argv = ::CommandLineToArgvW(full.c_str(), &argc);
  if (argv == nullptr) {
    return false;
  }
  std::wstring hook = argc > 1 ? argv[1] : L"";
  ::LocalFree(argv);
  for (auto& c : hook) {
    c = static_cast<wchar_t>(towlower(c));
  }
  if (hook.rfind(L"--veloapp-", 0) != 0) {
    return false;
  }
  // Velopack runs these with a time limit and only wants the process to
  // end; there is nothing else for the app to do in them.
  if (hook == L"--veloapp-install" || hook == L"--veloapp-updated") {
    RegisterMailHandler();
  } else if (hook == L"--veloapp-uninstall") {
    UnregisterMailHandler();
  }
  return true;
}
