import Foundation

enum Config {
    static let supabaseURL = "https://esziekejpiuquyjfquye.supabase.co"
    static let supabaseAnonKey: String = {
        if let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !key.isEmpty {
            return key
        }
        // Read from ~/.stickies-native.env
        if let home = ProcessInfo.processInfo.environment["HOME"],
           let data = FileManager.default.contents(atPath: "\(home)/.stickies-native.env"),
           let content = String(data: data, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "SUPABASE_ANON_KEY" {
                    return parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                }
            }
        }
        fatalError("SUPABASE_ANON_KEY not set. Create ~/.stickies-native.env with SUPABASE_ANON_KEY=your_key")
    }()
    static let appBaseURL = "http://localhost:4444"
    static let localApiKey: String = {
        if let key = ProcessInfo.processInfo.environment["STICKIES_API_KEY"], !key.isEmpty {
            return key
        }
        if let home = ProcessInfo.processInfo.environment["HOME"],
           let data = FileManager.default.contents(atPath: "\(home)/.stickies-native.env"),
           let content = String(data: data, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "STICKIES_API_KEY" {
                    return parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                }
            }
        }
        fatalError("STICKIES_API_KEY not set. Add it to ~/.stickies-native.env")
    }()
    static let callbackScheme = "stickiesnative"
    static let callbackURL = "\(callbackScheme)://auth/callback"
}
