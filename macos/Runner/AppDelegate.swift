import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Safety net: kill the local server process tree when the app terminates,
  /// in case the Flutter-side cleanup didn't finish in time.
  override func applicationWillTerminate(_ notification: Notification) {
    // Find any node process listening on port 9720 and kill it.
    let pipe = Pipe()
    let lsof = Process()
    lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    lsof.arguments = ["-ti", "tcp:9720"]
    lsof.standardOutput = pipe
    lsof.standardError = FileHandle.nullDevice
    try? lsof.run()
    lsof.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
      let pids = output.split(separator: "\n")
        .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
      for pid in pids {
        kill(pid, SIGKILL)
      }
    }
  }
}
