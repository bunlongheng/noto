import Foundation

enum Config {
    static let appBaseURL = "http://localhost:4444"

    /// The Stickies ext API key, or nil when it is not configured.
    /// Returns nil rather than calling fatalError so a missing key shows a setup
    /// message instead of crashing the app on launch.
    static let apiKey: String? = readEnv("STICKIES_API_KEY")

    private static func readEnv(_ key: String) -> String? {
        if let val = ProcessInfo.processInfo.environment[key], !val.isEmpty { return val }
        let path = "\(NSHomeDirectory())/.stickies-native.env"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            let val = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            return val.isEmpty ? nil : val
        }
        return nil
    }
}
