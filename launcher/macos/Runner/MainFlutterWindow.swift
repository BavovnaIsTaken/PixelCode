import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController

    self.minSize = NSSize(width: 400, height: 500)
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 450, height: 550), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
