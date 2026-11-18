import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Closing the window leaves Piuma in the Dock, still syncing and
  // notifying, as Mac apps do; clicking the Dock icon brings it back.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // mailto: links (CFBundleURLTypes), .eml files (CFBundleDocumentTypes)
  // and files dropped on the Dock icon, whether Piuma was running or
  // this started it. Untrusted: Dart checks each (lib/outside/).
  override func application(_ application: NSApplication, open urls: [URL]) {
    Shell.open(urls)
  }
}
