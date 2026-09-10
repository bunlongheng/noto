<div align="center">

<img src="docs/icon.png" width="104" alt="Stickies Native">

# Stickies Native

**A fast, read-only macOS window onto every note in [Stickies](https://github.com/bunlongheng/stickies).**

List all your notes, search them, open one, and find text inside it.

[![CI](https://github.com/bunlongheng/stickies-native/actions/workflows/ci.yml/badge.svg)](https://github.com/bunlongheng/stickies-native/actions/workflows/ci.yml)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Universal](https://img.shields.io/badge/binary-universal-4B8BBE)
![Dependencies](https://img.shields.io/badge/dependencies-0-success)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## What it does

| | |
|---|---|
| **Lists every note** | Pages the API until it is exhausted, in the same order as the web All view |
| **Search all notes** | Filters title and folder as you type, top left |
| **Open a note** | HTML notes render with their real styling; anything else as plain text |
| **Find in note** | Highlights every match with a live counter, top right |
| **Move to Trash** | Cmd+Delete, the Finder gesture |

## Shortcuts

| Key | Action |
|---|---|
| `Cmd` `Shift` `F` | Search all notes |
| `Cmd` `F` | Find in the open note |
| `Cmd` `Delete` | Move the selected note to TRASH |
| `Cmd` `R` | Refresh |

## Run it

```bash
git clone https://github.com/bunlongheng/stickies-native
cd stickies-native
echo 'STICKIES_API_KEY=sk_ext_your_key' > ~/.stickies-native.env
./build.sh --run
```

Requires macOS 14+, the Swift toolchain (Xcode Command Line Tools is enough), and a
Stickies server reachable at `http://localhost:4444`.

### Configuration

| Variable | Required | Where |
|---|---|---|
| `STICKIES_API_KEY` | yes | environment, or `~/.stickies-native.env` |

A missing key shows a setup message rather than crashing.

## Design

**Read-mostly on purpose.** The only write it performs is moving a note to TRASH.
It never edits note content - an earlier version round-tripped HTML through
`NSAttributedString` on a 3 second autosave, which silently rewrote hand-authored
markup. That whole path is gone.

**Trash is a move, not a delete.** `Cmd+Delete` issues the same PATCH the web app
does - `folder_name: "TRASH"` plus `trashed_at` - so the note stays recoverable
until the server's own 7 day cleanup. A hard delete is refused for API keys by
design, server side.

**Notes cannot execute anything.** Note HTML renders under a
`default-src 'none'` Content Security Policy, and script tags and inline handlers
are stripped before loading. The find highlighter runs in an isolated
`WKContentWorld`, which the CSP does not apply to - so it works while note scripts
stay blocked. Both halves are covered by tests.

## Layout

```
Sources/StickiesNative/
  App.swift            @main scene, menu commands, split view, toolbar
  AppState.swift       observable state: notes, selection, filter, toast
  Config.swift         API key resolution
  NoteIcon.swift       Heroicon / app tokens to SF Symbols
  NoteDetailView.swift WKWebView renderer, CSP, find highlighter
  Models/Note.swift    Codable model and formatting
  Models/APIClient.swift  read-only client, paging, trash
Tests/                 assertions, run by ./test.sh
```

## Tests

```bash
./test.sh
```

Compiles the sources and `Tests/` with `swiftc` and runs them. SwiftPM is not used:
`swift build` fails to link its manifest on a CommandLineTools-only toolchain, so
XCTest and swift-testing are unavailable there. This runs identically locally and in
CI and exits non-zero on failure.

## Build notes

`build.sh` produces a universal (arm64 + x86_64) bundle, compiled in **Swift 6
language mode** and signed ad-hoc. `Package.swift` is kept so the project also
builds under full Xcode, but `build.sh` is the supported path.

**Distribution:** local builds are ad-hoc signed, not notarized, so `spctl` rejects
them. Copying the `.app` to another Mac needs right-click then Open the first time.
Set `SIGN_IDENTITY` to build with a Developer ID instead.

## License

MIT - see [LICENSE](LICENSE).
