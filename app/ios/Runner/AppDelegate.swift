import Flutter
import UIKit
import SwiftUI
#if canImport(Translation)
  import Translation
#endif
#if canImport(FoundationModels)
  import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceModel") {
      OnDeviceModel.listen(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SavedFiles") {
      SavedFiles.listen(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Translate") {
      Translate.listen(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceName") {
      DeviceName.listen(registrar.messenger())
    }
  }
}

/// The device's name for Devices & sync: "iPad" or "iPhone", or the
/// name the person gave it where iOS shares it.
enum DeviceName {
  static func listen(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mail.piuma/device", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "name" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async { result(UIDevice.current.name) }
    }
  }
}

/// Saved attachments (`phone_files.dart`): iOS can't hand a file path to
/// another app, so the file opens in the system's preview, whose Share
/// button offers "Save to Files" and "Open in…".
final class SavedFiles: NSObject, UIDocumentInteractionControllerDelegate {
  static let shared = SavedFiles()
  private var showing: UIDocumentInteractionController?

  static func listen(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mail.piuma/files", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "open",
        let path = (call.arguments as? [String: Any])?["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        let preview = UIDocumentInteractionController(url: URL(fileURLWithPath: path))
        preview.delegate = SavedFiles.shared
        SavedFiles.shared.showing = preview
        if preview.presentPreview(animated: true) {
          result(nil)
        } else {
          result(FlutterError(code: "files", message: "No preview for this file", details: nil))
        }
      }
    }
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    var top = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first ?? UIViewController()
    while let shown = top.presentedViewController { top = shown }
    return top
  }

  func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
    showing = nil
  }
}

/// Apple Intelligence's on-device model (macOS and iOS 26), for "In short"
/// (`on_device_model.dart`). Without it the app keeps its own rules.
enum OnDeviceModel {
  static func listen(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mail.piuma/model", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "status":
        result(status())
      case "generate":
        let prompt = (call.arguments as? [String: Any])?["prompt"] as? String ?? ""
        Task {
          do {
            let text = try await generate(prompt)
            await MainActor.run { result(text) }
          } catch {
            await MainActor.run {
              result(FlutterError(code: "model", message: error.localizedDescription, details: nil))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// "off" and "downloading" are asked again next time: the person may
  /// turn Apple Intelligence on, and the model may finish downloading.
  static func status() -> String {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, iOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return "available"
        case .unavailable(.modelNotReady):
          return "downloading"
        case .unavailable(.appleIntelligenceNotEnabled):
          return "off"
        default:
          return "unavailable"
        }
      }
    #endif
    return "unavailable"
  }

  static func generate(_ prompt: String) async throws -> String? {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, iOS 26.0, *) {
        let session = LanguageModelSession()
        let response = try await session.respond(
          to: prompt,
          options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 160)
        )
        return response.content
      }
    #endif
    return nil
  }
}

/// Apple's own translation (macOS 15, iOS 18 and later), for Translate in
/// the reader (`translator.dart`). It runs on the device; a language not
/// yet downloaded is offered by the system first. The framework hands out
/// sessions only to a SwiftUI view, so a tiny one is added while it works.
enum Translate {
  enum Failure: Error {
    case unavailable
    case noWindow
  }

  static func listen(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mail.piuma/translate", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let from = args["from"] as? String ?? ""
      let to = args["to"] as? String ?? ""
      switch call.method {
      case "status":
        Task { @MainActor in
          result(await status(from, to))
        }
      case "translate":
        let texts = args["texts"] as? [String] ?? []
        Task { @MainActor in
          do {
            result(try await translate(texts, from, to))
          } catch {
            // Done on the system's download sheet without downloading.
            let missing = await status(from, to) != "installed"
            result(FlutterError(
              code: missing ? "download" : "translate",
              message: error.localizedDescription, details: nil))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// "installed", "supported" (downloaded first) or "unsupported".
  static func status(_ from: String, _ to: String) async -> String {
    #if canImport(Translation)
      if #available(macOS 15.0, iOS 18.0, *) {
        let status = await LanguageAvailability().status(
          from: Locale.Language(identifier: from),
          to: Locale.Language(identifier: to)
        )
        switch status {
        case .installed:
          return "installed"
        case .supported:
          return "supported"
        default:
          return "unsupported"
        }
      }
    #endif
    return "unsupported"
  }

  @MainActor
  static func translate(_ texts: [String], _ from: String, _ to: String) async throws -> [String] {
    #if canImport(Translation)
      if #available(macOS 15.0, iOS 18.0, *) {
        return try await withCheckedThrowingContinuation { done in
          let job = TranslateJob(done)
          let view = TranslateHost(
            configuration: TranslationSession.Configuration(
              source: Locale.Language(identifier: from),
              target: Locale.Language(identifier: to)
            )
          ) { session in
            do {
              try await session.prepareTranslation()
              let requests = texts.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
              }
              var out = texts
              for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier, let i = Int(id), i < out.count {
                  out[i] = response.targetText
                }
              }
              await job.finish(.success(out))
            } catch {
              await job.finish(.failure(error))
            }
          }
          job.host = attach(view)
          if job.host == nil {
            job.finish(.failure(Failure.noWindow))
          }
        }
      }
    #endif
    throw Failure.unavailable
  }
}

#if canImport(Translation)
  /// One translation: answers Flutter once, then takes its view away.
  @MainActor
  final class TranslateJob {
    private var done: CheckedContinuation<[String], Error>?
    var host: AnyObject?

    init(_ done: CheckedContinuation<[String], Error>) {
      self.done = done
    }

    func finish(_ result: Result<[String], Error>) {
      done?.resume(with: result)
      done = nil
      detach(host)
      host = nil
    }
  }

  @available(macOS 15.0, iOS 18.0, *)
  struct TranslateHost: View {
    let configuration: TranslationSession.Configuration
    let work: (TranslationSession) async -> Void

    var body: some View {
      Color.clear
        .frame(width: 1, height: 1)
        .translationTask(configuration) { session in
          await work(session)
        }
    }
  }

  @MainActor
  func attach<V: View>(_ view: V) -> AnyObject? {
    var top = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
    while let shown = top?.presentedViewController { top = shown }
    guard let parent = top else { return nil }
    let hosting = UIHostingController(rootView: view)
    hosting.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    hosting.view.backgroundColor = .clear
    parent.addChild(hosting)
    parent.view.addSubview(hosting.view)
    hosting.didMove(toParent: parent)
    return hosting
  }

  @MainActor
  func detach(_ host: AnyObject?) {
    guard let hosting = host as? UIViewController else { return }
    hosting.willMove(toParent: nil)
    hosting.view.removeFromSuperview()
    hosting.removeFromParent()
  }
#endif
