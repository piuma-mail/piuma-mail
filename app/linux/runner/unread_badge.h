#ifndef RUNNER_UNREAD_BADGE_H_
#define RUNNER_UNREAD_BADGE_H_

#include <flutter_linux/flutter_linux.h>

// How many emails are unread, in the window's title ("Piuma Mail (3)"):
// Linux desktops have no common badge on an app's icon.
void unread_badge_register(FlPluginRegistrar* registrar);

#endif  // RUNNER_UNREAD_BADGE_H_
