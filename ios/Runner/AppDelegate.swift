import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let clipboardChannel = FlutterMethodChannel(
        name: "com.pixelcode/clipboard",
        binaryMessenger: controller.binaryMessenger
      )
      clipboardChannel.setMethodCallHandler { (call, result) in
        if call.method == "getImageFromClipboard" {
          DispatchQueue.main.async {
            if UIPasteboard.general.hasImages,
               let image = UIPasteboard.general.image,
               let pngData = image.pngData() {
              result(FlutterStandardTypedData(bytes: pngData))
            } else {
              result(nil)
            }
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
