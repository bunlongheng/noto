import AppKit

/// Maps the icon token the API stores on a note to an SF Symbol.
///
/// Stickies stores either "__hero:<HeroiconName>" (the web app renders Heroicons)
/// or "__<app>" / "__app:<name>" for notes posted by a specific tool. Neither set
/// exists on macOS, so each is mapped to the closest SF Symbol. Every result is
/// checked against the running system before use - an unavailable symbol name
/// renders as nothing, which would leave a blank row.
enum NoteIcon {
    private static let fallback = "doc.text.fill"

    private static let hero: [String: String] = [
        "CheckCircleIcon": "checkmark.circle.fill",
        "ChartBarIcon": "chart.bar.fill",
        "RocketLaunchIcon": "paperplane.fill",
        "ClipboardDocumentListIcon": "doc.on.clipboard",
        "ArrowPathIcon": "arrow.triangle.2.circlepath",
        "EnvelopeIcon": "envelope.fill",
        "LinkIcon": "link",
        "GlobeAltIcon": "globe",
        "UserGroupIcon": "person.2.fill",
        "SwatchIcon": "paintpalette.fill",
        "BriefcaseIcon": "briefcase.fill",
        "RobotIcon": "cpu",
        "KeyIcon": "key.fill",
        "FolderIcon": "folder.fill",
        "BookOpenIcon": "book.fill",
        "CodeBracketIcon": "chevron.left.forwardslash.chevron.right",
        "WrenchIcon": "wrench.fill",
        "MagnifyingGlassIcon": "magnifyingglass",
        "DocumentTextIcon": "doc.text.fill",
        "LightBulbIcon": "lightbulb.fill",
        "BugAntIcon": "ladybug.fill",
        "HomeIcon": "house.fill",
        "TableCellsIcon": "tablecells.fill",
        "CalendarDaysIcon": "calendar",
        "ChatBubbleLeftRightIcon": "bubble.left.and.bubble.right.fill",
        "ShareIcon": "square.and.arrow.up",
        "GlobeAmericasIcon": "globe.americas.fill",
        "DevicePhoneMobileIcon": "iphone",
        "PhotoIcon": "photo.fill",
        "FilmIcon": "film.fill",
        "BanknotesIcon": "banknote",
        "StarIcon": "star.fill",
        "PuzzlePieceIcon": "puzzlepiece.fill",
        "SparklesIcon": "sparkles",
        "IdentificationIcon": "person.text.rectangle",
        "QuestionMarkCircleIcon": "questionmark.circle.fill",
        "BoltIcon": "bolt.fill",
        "MusicalNoteIcon": "music.note",
        "CubeTransparentIcon": "cube.transparent",
    ]

    private static let app: [String: String] = [
        "repoaudit": "magnifyingglass.circle.fill",
        "praudit": "magnifyingglass.circle.fill",
        "skillaudit": "magnifyingglass.circle.fill",
        "epicaudit": "magnifyingglass.circle.fill",
        "devaudit": "magnifyingglass.circle.fill",
        "portfolioaudit": "magnifyingglass.circle.fill",
        "githubaudit": "magnifyingglass.circle.fill",
        "resourceaudit": "magnifyingglass.circle.fill",
        "projectaudit": "magnifyingglass.circle.fill",
        "reporecon": "binoculars.fill",
        "repotest": "checkmark.seal.fill",
        "gmail": "envelope.fill",
        "linkedin": "person.crop.square.fill",
        "github": "chevron.left.forwardslash.chevron.right",
        "prtrends": "chart.line.uptrend.xyaxis",
        "githubstats": "chart.line.uptrend.xyaxis",
        "prsummary": "chart.line.uptrend.xyaxis",
        "app:fable": "sparkles",
        "app:repo-audit": "magnifyingglass.circle.fill",
        "app:worldcup26": "soccerball",
        "app:skill-architect": "hammer.fill",
        "app:job": "briefcase.fill",
        "app:incident-report": "exclamationmark.triangle.fill",
        "app:countries": "globe.americas.fill",
        "app:bheng": "person.crop.circle.fill",
        "app:rust": "chevron.left.forwardslash.chevron.right",
        "app:react": "chevron.left.forwardslash.chevron.right",
        "app:laravel": "chevron.left.forwardslash.chevron.right",
        "app:next.js": "chevron.left.forwardslash.chevron.right",
        "app:typescript": "chevron.left.forwardslash.chevron.right",
    ]

    /// An SF Symbol name guaranteed to exist on this system.
    static func symbol(for token: String?) -> String {
        guard let token, token.hasPrefix("__") else { return fallback }
        let body = String(token.dropFirst(2))
        let name = body.hasPrefix("hero:")
            ? hero[String(body.dropFirst(5))]
            : app[body]
        guard let name, exists(name) else { return fallback }
        return name
    }

    private static var checked: [String: Bool] = [:]

    private static func exists(_ name: String) -> Bool {
        if let known = checked[name] { return known }
        let ok = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        checked[name] = ok
        return ok
    }
}
