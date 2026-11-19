#include "window_place.h"

#include <string>

#include "start_menu.h"

namespace {

std::wstring KeyPath() {
  return IsDevCopy() ? L"Software\\PiumaMail.Dev\\Window"
                     : L"Software\\PiumaMail\\Window";
}

constexpr wchar_t kPlacement[] = L"Placement";

}  // namespace

bool RestoreWindowPlace(HWND window) {
  WINDOWPLACEMENT place{};
  DWORD size = sizeof(place);
  if (::RegGetValueW(HKEY_CURRENT_USER, KeyPath().c_str(), kPlacement,
                     RRF_RT_REG_BINARY, nullptr, &place,
                     &size) != ERROR_SUCCESS ||
      size != sizeof(place) || place.length != sizeof(place)) {
    return false;
  }
  const RECT& r = place.rcNormalPosition;
  // A screen unplugged since, or a size that makes no sense: the default.
  if (r.right - r.left < 200 || r.bottom - r.top < 200 ||
      ::MonitorFromRect(&r, MONITOR_DEFAULTTONULL) == nullptr) {
    return false;
  }
  const bool maximized = place.showCmd == SW_SHOWMAXIMIZED;
  // Placed while hidden: Show() then shows it normal or maximized.
  place.showCmd = SW_HIDE;
  place.flags = 0;
  ::SetWindowPlacement(window, &place);
  return maximized;
}

void SaveWindowPlace(HWND window) {
  if (window == nullptr || ::IsIconic(window) || !::IsWindowVisible(window)) {
    return;
  }
  WINDOWPLACEMENT place{};
  place.length = sizeof(place);
  if (!::GetWindowPlacement(window, &place)) return;
  place.showCmd = ::IsZoomed(window) ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  HKEY key;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, KeyPath().c_str(), 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  ::RegSetValueExW(key, kPlacement, 0, REG_BINARY,
                   reinterpret_cast<const BYTE*>(&place), sizeof(place));
  ::RegCloseKey(key);
}
