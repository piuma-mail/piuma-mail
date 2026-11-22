import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Over the app while it leaves the screen, so the app switcher's
  /// snapshot shows no mail while the app lock is on.
  private var cover: UIView?

  /// The app lock is on while `app-lock.json` is next to the database
  /// (`app/lib/lock/`), in Application Support.
  private var lockOn: Bool {
    guard
      let dir = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { return false }
    return FileManager.default.fileExists(
      atPath: dir.appendingPathComponent("app-lock.json").path)
  }

  override init() {
    super.init()
    // Notifications rather than overrides: FlutterSceneDelegate keeps its
    // own scene callbacks for the plugins.
    NotificationCenter.default.addObserver(
      self, selector: #selector(leaving), name: UIScene.willDeactivateNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(back), name: UIScene.didActivateNotification, object: nil)
  }

  @objc private func leaving() {
    guard lockOn, cover == nil, let window = window else { return }
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.backgroundColor = .systemBackground
    let logo = UIImageView(image: UIImage(named: "LaunchImage"))
    logo.contentMode = .center
    logo.frame = view.bounds
    logo.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(logo)
    window.addSubview(view)
    cover = view
  }

  @objc private func back() {
    cover?.removeFromSuperview()
    cover = nil
  }
}
