#ifndef RUNNER_START_MENU_H_
#define RUNNER_START_MENU_H_

// True for a build the installer didn't put in place (`flutter run`, a
// test build): it keeps its own shortcut, notices and folder, so it never
// touches the copy installed on the same PC (lib/dev_copy.dart).
bool IsDevCopy();

// Windows shows a desktop program's notices only when a Start menu
// shortcut carries the id they are sent with. Puts "Piuma Mail" (or
// "Piuma Mail (dev)" for a dev copy) in the user's Start menu, pointing at
// this program, unless it is already there. Needs COM.
void RegisterStartMenu();

#endif  // RUNNER_START_MENU_H_
