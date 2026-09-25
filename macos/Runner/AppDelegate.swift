import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingLaunchFile: String?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Expose any file macOS asked us to open to the Dart side.
    let controller = NSApplication.shared.windows.first?.contentViewController
      as? FlutterViewController
    if let controller = controller {
      let channel = FlutterMethodChannel(
        name: "hue_cai/launch",
        binaryMessenger: controller.engine.binaryMessenger
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
    super.applicationDidFinishLaunching(notification)
  }

  /// Finder's "Open With" / double-click delivers the document here.
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    if let path = filenames.first(where: {
      $0.lowercased().hasSuffix(".hcproj") || $0.lowercased().hasSuffix(".hcp")
    }) {
      pendingLaunchFile = path
    }
    sender.reply(toOpenOrPrint: .success)
  }
}
