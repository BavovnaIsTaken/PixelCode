import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let frameKey = "PixelCode.lastWindowFrame"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Hide native title bar and traffic lights
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.pixelcode/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "animateShutdown" {
        self?.animateShutdown()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let clipboardChannel = FlutterMethodChannel(
      name: "com.pixelcode/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel.setMethodCallHandler { (call, result) in
      if call.method == "getImageFromClipboard" {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
          result(FlutterStandardTypedData(bytes: pngData))
        } else {
          result(nil)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    // If we have a saved frame from last shutdown, open with expand animation
    if let dict = UserDefaults.standard.dictionary(forKey: Self.frameKey),
       let x = dict["x"] as? CGFloat,
       let y = dict["y"] as? CGFloat,
       let w = dict["w"] as? CGFloat,
       let h = dict["h"] as? CGFloat {
      let targetFrame = NSRect(x: x, y: y, width: w, height: h)
      let cy = targetFrame.midY
      let collapsed = NSRect(x: x, y: cy - 25, width: w, height: 50)
      self.setFrame(collapsed, display: false)
      self.makeKeyAndOrderFront(nil)

      // Animate expand
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        NSAnimationContext.runAnimationGroup { ctx in
          ctx.duration = 0.45
          ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
          self.animator().setFrame(targetFrame, display: true)
        }
      }

      UserDefaults.standard.removeObject(forKey: Self.frameKey)
    }
  }

  private func animateShutdown() {
    let frame = self.frame
    let cy = frame.midY

    // Save current frame for next launch
    UserDefaults.standard.set([
      "x": frame.origin.x,
      "y": frame.origin.y,
      "w": frame.width,
      "h": frame.height,
    ], forKey: Self.frameKey)

    // Collapse vertically to 50px height, then terminate
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.55
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      self.animator().setFrame(
        NSRect(x: frame.origin.x, y: cy - 25, width: frame.width, height: 50),
        display: true
      )
    }) {
      NSApplication.shared.terminate(nil)
    }
  }
}
