#ifndef RUNNER_MAIL_HANDLER_H_
#define RUNNER_MAIL_HANDLER_H_

#include <string>

// Piuma as a mail app Windows knows: it opens mailto: links and .eml
// files, and is listed in Settings > Apps > Default apps. Everything is
// per user (HKCU\Software\Classes and HKCU\Software\RegisteredApplications),
// written by the installer's hooks and removed when Piuma is uninstalled.
// Registering never takes the default from another app: Windows lets
// only the person choose it, in Default apps.

// Adds or refreshes the registration for this program.
void RegisterMailHandler();

// Removes everything RegisterMailHandler and SetStartAtLogin wrote.
void UnregisterMailHandler();

// "piuma", "other" or "none": who opens mailto: links now.
std::string DefaultMailState();

// Opens Piuma's page of Settings > Apps > Default apps (registering first,
// so the page is there).
void OpenDefaultAppsSettings();

// Starts Piuma at sign-in, without its window ("--background"), or stops.
void SetStartAtLogin(bool on);

// Handles Velopack's installer hooks (--veloapp-install, -updated,
// -obsolete, -uninstall). True when the command line was one: the
// process ends then, without a window.
bool HandleInstallerHook(const wchar_t* command_line);

#endif  // RUNNER_MAIL_HANDLER_H_
