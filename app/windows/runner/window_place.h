#ifndef RUNNER_WINDOW_PLACE_H_
#define RUNNER_WINDOW_PLACE_H_

#include <windows.h>

// Where the inbox window was, kept per user under
// HKCU\Software\PiumaMail\Window (the dev copy's under PiumaMail.Dev), so
// the next launch opens it at the same size and place, maximized if it
// was. Uninstalling removes the key with the rest.

// Moves the (still hidden) |window| to its last place, when that is on a
// screen that is still there. True when it was maximized.
bool RestoreWindowPlace(HWND window);

// Keeps where |window| is now; nothing while it is minimized.
void SaveWindowPlace(HWND window);

#endif  // RUNNER_WINDOW_PLACE_H_
