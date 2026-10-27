import AppKit
import SwiftUI

/// Maps the icon token the API stores on a note to an SF Symbol.
///
/// The server stores either "__hero:<HeroiconName>" (the web app renders Heroicons)
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
        "ShareIcon": "point.3.connected.trianglepath.dotted",
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
        "EyeIcon": "eye.fill",
        "MusicalNoteIcon": "music.note",
        "CubeTransparentIcon": "cube.transparent",
        "UsersIcon": "person.3.fill",
        "LockOpenIcon": "lock.open.fill",
        "CloudIcon": "cloud.fill",
        "AcademicCapIcon": "graduationcap.fill",
        "ArchiveBoxIcon": "archivebox.fill",
        "BeakerIcon": "flask.fill",
        "BellIcon": "bell.fill",
        "BuildingOfficeIcon": "building.2.fill",
        "ChartBarSquareIcon": "chart.bar.xaxis",
        "CheckIcon": "checkmark",
        "ClipboardIcon": "clipboard.fill",
        "ClockIcon": "clock.fill",
        "Cog6ToothIcon": "gearshape.fill",
        "ComputerDesktopIcon": "desktopcomputer",
        "CpuChipIcon": "cpu.fill",
        "DocumentDuplicateIcon": "doc.on.doc.fill",
        "ExclamationTriangleIcon": "exclamationmark.triangle.fill",
        "FingerPrintIcon": "touchid",
        "FlagIcon": "flag.fill",
        "HeartIcon": "heart.fill",
        "InboxIcon": "tray.fill",
        "MapPinIcon": "mappin",
        "RectangleStackIcon": "square.stack.fill",
        "ServerIcon": "server.rack",
        "ShieldCheckIcon": "checkmark.shield.fill",
        "Squares2X2Icon": "square.grid.2x2.fill",
        "TagIcon": "tag.fill",
        "TrophyIcon": "trophy.fill",
        "UserIcon": "person.fill",
        "WrenchScrewdriverIcon": "wrench.and.screwdriver.fill",
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
        "securityaudit": "magnifyingglass.circle.fill",
        "storageaudit": "magnifyingglass.circle.fill",
        "claude": "sparkle",
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
        "app:jobs": "briefcase.fill",
        "app:sequences": "arrow.left.arrow.right",
        "app:flows": "arrow.triangle.branch",
        "app:mindmaps": "point.3.connected.trianglepath.dotted",
    ]

    /// An SF Symbol name guaranteed to exist on this system. Mirrors the web
    /// FolderIconDisplay: "__hero:" and "__<token>" values get a glyph, anything
    /// else (no icon, or a value the web would not render) shows the title's first
    /// letter or digit on the note colour, exactly like the web tile.
    static func symbol(for token: String?, title: String = "") -> String {
        guard let token, token.hasPrefix("__") else { return initial(title) }
        let body = String(token.dropFirst(2))
        let name = body.hasPrefix("hero:")
            ? hero[String(body.dropFirst(5))]
            : app[body]
        guard let name, exists(name) else { return fallback }
        return name
    }

    /// lib/text.ts meaningfulInitial: first letter or digit, fallback "N".
    private static func initial(_ title: String) -> String {
        let first = title.first { $0.isLetter || $0.isNumber }.map { String($0).lowercased() } ?? "n"
        let name = "\(first).square.fill"
        return exists(name) ? name : fallback
    }

    /// Tokens drawn by `NoteIconView` because no single SF Symbol fits.
    static func isComposite(_ token: String?) -> Bool { token == "__userrecon" }

    /// Computed once, immutable, therefore Sendable - a mutable static cache was
    /// a hard error under the Swift 6 language mode the package declares.
    private static let available: Set<String> = Set(
        (Array(hero.values) + Array(app.values)
            + "abcdefghijklmnopqrstuvwxyz0123456789".map { "\($0).square.fill" }).filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    )

    private static func exists(_ name: String) -> Bool { available.contains(name) }
}

/// A note's icon. Composite tokens are layered from 2 symbols; everything else
/// is the plain SF Symbol, so `.font` and `.foregroundStyle` apply the same way.
struct NoteIconView: View {
    let token: String?
    var title: String = ""

    var body: some View {
        if NoteIcon.isComposite(token) {
            // __userrecon: a person inside the lens of a magnifying glass.
            // Scaling about this anchor lands the person's centre on the lens
            // centre (about 41% in on both axes), at any font size.
            ZStack {
                Image(systemName: "magnifyingglass")
                Image(systemName: "person.fill")
                    .scaleEffect(0.42, anchor: UnitPoint(x: 0.345, y: 0.345))
            }
        } else {
            Image(systemName: NoteIcon.symbol(for: token, title: title))
        }
    }
}
