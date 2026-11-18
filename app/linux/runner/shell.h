#ifndef RUNNER_SHELL_H_
#define RUNNER_SHELL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The app's window and the rest of the desktop (lib/outside/ in Dart, over
// the "piuma/shell" channel): later launches' command lines (a mailto:
// link, an .eml file), staying in the tray while the window is closed
// (StatusNotifierItem through libayatana-appindicator or libappindicator,
// loaded when the system has one; without it closing quits), starting at
// sign-in, the default mail app (through the
// installed .desktop file), and the unread count on the launcher (Unity
// LauncherEntry, read by Ubuntu's dock, Dash to Dock and KDE Plasma).
typedef struct _Shell Shell;

// Made once, for the inbox's window and view.
Shell* shell_new(GApplication* application, GtkWindow* window, FlView* view);

// A later launch's arguments, without the program.
void shell_forward(Shell* shell, gchar** arguments);

// Brings the window forward (a later launch, the tray).
void shell_present(Shell* shell);

#endif  // RUNNER_SHELL_H_
