import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var pendingLaunchFile: String?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // A document opened from Files arrives as a URL context.
    if let url = connectionOptions.urlContexts.first?.url {
      pendingLaunchFile = Self.projectPath(from: url)
    }

    guard let windowScene = scene as? UIWindowScene,
          let controller = windowScene.windows.first?.rootViewController
            as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "hue_cai/launch",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getLaunchFile" {
        result(self?.pendingLaunchFile)
        self?.pendingLaunchFile = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// "Open in HueCai" on an already-running app.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      pendingLaunchFile = Self.projectPath(from: url)
    }
  }

  /// Normalizes a document URL to a local path for `.hcproj` / `.hcp`.
  private static func projectPath(from url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    guard ext == "hcproj" || ext == "hcp" else { return nil }
    // Files opened in-place may need security-scoped access.
    _ = url.startAccessingSecurityScopedResource()
    return url.path
  }
}
