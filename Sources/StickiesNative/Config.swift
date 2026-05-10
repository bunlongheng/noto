import Foundation

enum Config {
    static let supabaseURL = "https://esziekejpiuquyjfquye.supabase.co"
    static let supabaseAnonKey = "***REMOVED***"
    static let appBaseURL = "https://stickies-bheng.vercel.app"
    /// Custom URL scheme for OAuth callback
    static let callbackScheme = "stickiesnative"
    static let callbackURL = "\(callbackScheme)://auth/callback"
}
