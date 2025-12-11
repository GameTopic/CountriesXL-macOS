import Foundation

// This helper was originally a standalone script. To avoid compiler errors when the file
// is included in the app target, we wrap the logic in a function so there are no top-level
// statements. To run it as a script, you can copy the body into a separate .swift file
// and run `swift <file>.swift` or call this function from a small main program.

func extractSettingsStrings() {
    let fm = FileManager.default
    let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent().deletingLastPathComponent()
    let settingsPath = projectRoot.appendingPathComponent("CountriesXL/CountriesXL/CountriesXL")

    func files(in dir: URL) -> [URL] {
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "swift" {
                urls.append(url)
            }
        }
        return urls
    }

    let swiftFiles = files(in: settingsPath)

    var results: [String: [(String, Int)]] = [:] // file -> [(literal, line)]

    for file in swiftFiles {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            let s = String(line)
            // naive scanning for string literals inside UI calls
            if s.contains("Text(") || s.contains("Button(") || s.contains("Toggle(") || s.contains("Picker(") || s.contains("Section(header: Text(") || s.contains("help(") {
                // extract quoted substrings
                let regex = try! NSRegularExpression(pattern: "\"(.*?)\"", options: [])
                let ns = s as NSString
                let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    let lit = ns.substring(with: m.range(at: 1))
                    // ignore empty or format-looking items
                    if lit.isEmpty { continue }
                    if lit.contains("%@") { continue }
                    if lit.contains("%d") { continue }
                    results[file.path, default: []].append((lit, i+1))
                }
            }
        }
    }

    print("Found candidate UI string literals in the following files:\n")
    for (file, entries) in results.sorted(by: { $0.key < $1.key }) {
        print("\nFile: \(file)")
        for (lit, line) in entries {
            print("  L\(line): \"\(lit)\"")
        }
    }

    print("\nSuggestion: Run this script from the project's Localization directory. It will help identify strings to localize.")
}

// Note: No top-level execution to avoid being treated as a script when compiled into the app.
// To run interactively, from the Localization folder run:
// swift extract_settings_strings.swift



