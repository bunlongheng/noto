# StickiesNative

A native macOS client for [Stickies](https://github.com/bunlongheng) - a two-pane SwiftUI editor for browsing, writing, and syncing notes stored on the Stickies web app, with rich text, drag-and-drop images, and autosave.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0066CC?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-000000?logo=apple&logoColor=white)

## Features

- Two-pane window (`NavigationSplitView`) - a searchable note list on the left, a rich text editor on the right.
- Live search across note title and folder name.
- Rich text editing via an `NSTextView` bridge: bold, italic, underline, left/center/right alignment, bullet lists, a markdown-table insert, and a font-size menu (12-32pt).
- Autosave - edits save automatically 3 seconds after you stop typing, plus a manual save with `Cmd+S`; a "Saving..." / "Unsaved" indicator sits in the editor title bar.
- Drag-and-drop or pasted images are uploaded to the Stickies backend's Google Drive endpoint and swapped inline for an `<img>` tag before the note saves.
- New Note sheet (title + folder name).
- Light / Dark / Auto theme, toggled from the sidebar icon or the app's `Theme` menu, persisted with `@AppStorage`.
- Folder color dot and last-updated timestamp shown per note.

## How it works

StickiesNative holds no local note database - it's a thin client over the Stickies web app's REST API. Every note lives on a Stickies server; the app fetches, edits, and writes it back as HTML.

| File | Role |
|------|------|
| `App.swift` | Entry point - owns `AppState` (notes, search, loading, selection) and sets the API token on launch |
| `Views/ContentView.swift` | The split-view shell (sidebar + editor) |
| `Views/SidebarView.swift` | Search field, note list, new-note sheet, refresh, theme toggle |
| `Views/EditorView.swift` | Per-note title bar, autosave timer, image-upload pipeline, and the `NSTextView`-backed editor |
| `Views/ToolbarView.swift` | Formatting commands, applied to the focused `NSTextView` via `NSFontManager` and paragraph styles |
| `Models/Note.swift` | The `Note` model plus folder-color and date-display helpers |
| `Models/APIClient.swift` | The only networking code - Bearer-token requests to the Stickies REST API |
| `Config.swift` | Reads `STICKIES_API_KEY` (env var or `~/.stickies-native.env`) and the Stickies base URL |

Sync flow: on launch the app sets the API token and calls `GET /api/stickies/ext` to list notes, then `GET /api/stickies/ext?id=` to lazy-load a note's content when it's selected. Edits are written back with `PATCH /api/stickies/ext`; new notes with `POST /api/stickies/ext`. Any image dropped or pasted into the editor is uploaded with `POST /api/stickies/gdrive`, and the returned URL replaces the image inline as `<img src="..." style="max-width:100%">` - notes are stored as HTML, the same format the Stickies web app itself uses.

Auth is a single bearer API key, not a sign-in screen - there is no OAuth flow wired up in the current app.

## Tech stack

| Layer | Choice |
|-------|--------|
| Language | Swift 6 |
| UI | SwiftUI (windows, split view, sidebar, forms) + AppKit (`NSTextView` rich-text editing, `NSFontManager`) |
| Networking | `URLSession` - Bearer-token REST calls and multipart image upload |
| Build | Swift Package Manager (`Package.swift`, swift-tools-version 6.0) plus a standalone `swiftc` build script |
| Target | macOS 14+ (Sonoma), arm64 |
| Local storage | None for notes - only the theme preference is persisted, via `@AppStorage` |
| License | MIT |

## Getting started

StickiesNative needs a running Stickies backend to talk to (defaults to `http://localhost:4444` in `Config.swift`) and an API key for it.

Create `~/.stickies-native.env`:

```
STICKIES_API_KEY=sk_ext_your_api_key_here
```

(or export `STICKIES_API_KEY` as an environment variable instead.)

## Build

Two ways to build, no external package dependencies:

**Swift Package Manager / Xcode**

```bash
swift build
swift run
# or: open Package.swift to work on it in Xcode
```

**Standalone script** (invokes `swiftc` against the Command Line Tools SDK directly and stages a `.app` bundle)

```bash
./build.sh          # produces ./StickiesNative and ./StickiesNative.app
./build.sh --run    # build and launch
```

`build.sh` also writes the `Info.plist` for the bundle (`com.bheng.stickies-native`, minimum macOS 14.0).

## License

MIT - see [LICENSE](LICENSE).
