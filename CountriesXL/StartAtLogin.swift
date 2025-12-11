import Foundation
import ServiceManagement

enum StartAtLoginHelper {
    static func setEnabled(_ enabled: Bool) throws {
        // SMAppService for Login Item requires a helper target. As a fallback for a single target app,
        // we can use a LaunchAgent plist in ~/Library/LaunchAgents.
        try LaunchAgent.setEnabled(enabled)
    }
}

private enum LaunchAgent {
    private static var plistURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("com.countriesxl.launchagent.plist")
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writePlist()
            _ = try? shell("launchctl", ["load", plistURL.path])
        } else {
            _ = try? shell("launchctl", ["unload", plistURL.path])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func writePlist() throws {
        let appPath = Bundle.main.bundlePath
        let dict: [String: Any] = [
            "Label": "com.countriesxl.launchagent",
            "Program": appPath + "/Contents/MacOS/" + (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "CountriesXL"),
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    @discardableResult
    private static func shell(_ launchPath: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/\(launchPath)".replacingOccurrences(of: "/usr/bin//", with: "/usr/bin/")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
