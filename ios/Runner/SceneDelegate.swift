import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  private static let frameKey = "PixelCode.lastWindowCollapsed"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let flutterVC = window?.rootViewController as? FlutterViewController else { return }
    setupWindowChannel(messenger: flutterVC.binaryMessenger)
  }

  // MARK: - MethodChannel

  private func setupWindowChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelcode/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "animateShutdown" {
        self?.animateShutdown()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Launch expand animation if we were previously collapsed
    if UserDefaults.standard.bool(forKey: Self.frameKey) {
      UserDefaults.standard.removeObject(forKey: Self.frameKey)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.animateLaunchExpand()
      }
    }
  }

  // MARK: - Animations

  /// Collapse the window to a thin horizontal bar, then terminate.
  private func animateShutdown() {
    guard let keyWindow = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow }) else { return }

    let screen = keyWindow.bounds
    let barHeight: CGFloat = 50
    let targetFrame = CGRect(
      x: 0,
      y: (screen.height - barHeight) / 2,
      width: screen.width,
      height: barHeight
    )

    // Save flag before animating — synchronize ensures it's written before exit(0)
    UserDefaults.standard.set(true, forKey: Self.frameKey)
    UserDefaults.standard.synchronize()

    UIView.animate(
      withDuration: 0.55,
      delay: 0,
      options: [.curveEaseIn],
      animations: {
        keyWindow.frame = targetFrame
        keyWindow.layer.cornerRadius = 8
      },
      completion: { _ in
        exit(0)
      }
    )
  }

  /// Expand from a thin bar to full screen on launch.
  private func animateLaunchExpand() {
    guard let keyWindow = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow }) else { return }

    let screen = UIScreen.main.bounds
    let barHeight: CGFloat = 50

    // Start collapsed
    keyWindow.frame = CGRect(
      x: 0,
      y: (screen.height - barHeight) / 2,
      width: screen.width,
      height: barHeight
    )
    keyWindow.layer.cornerRadius = 8

    UIView.animate(
      withDuration: 0.45,
      delay: 0,
      options: [.curveEaseOut],
      animations: {
        keyWindow.frame = screen
        keyWindow.layer.cornerRadius = 0
      }
    )
  }
}
