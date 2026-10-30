<div align="center">

<img src="docs/icon.png" width="104" alt="Noto">

# Noto

**A fast native macOS window onto every note you own.**

*Noto - ノート - notes.*

List all your notes, search titles and text, open one, find inside it, and write a new one.

[![CI](https://github.com/bunlongheng/noto/actions/workflows/ci.yml/badge.svg)](https://github.com/bunlongheng/noto/actions/workflows/ci.yml)
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
| **Filter the list** | The sidebar field narrows the loaded list by title and folder, as you type |
| **Search all notes** | `Cmd+Shift+F` matches titles locally and note TEXT on the server |
| **New note** | `Cmd+N` writes a plain-text note |
| **Open a note** | HTML notes render with their real styling; anything else as plain text |
| **Find in note** | Highlights every match with a live counter, top right |
| **Move to Trash** | Cmd+Delete, the Finder gesture |

## Shortcuts

| Key | Action |
|---|---|
| `Cmd` `Shift` `F` | Search all notes, titles and text |
| `Cmd` `N` | New plain-text note |
| `Cmd` `F` | Find in the open note |
| `Cmd` `Delete` | Move the selected note to TRASH |
| `Cmd` `R` | Refresh |

## Run it

```bash
git clone https://github.com/bunlongheng/noto
cd noto
echo 'NOTO_API_KEY=sk_ext_your_key' > ~/.noto.env
./build.sh --install   # into /Applications, then launch it
```

`--run` builds and launches in place. `--install` copies the bundle to
`/Applications` so Launchpad, Spotlight and the Dock can open it; every later
`./build.sh` refreshes that installed copy automatically.

Requires macOS 14+, the Swift toolchain (Xcode Command Line Tools is enough), and the
notes server ([bunlongheng/stickies](https://github.com/bunlongheng/stickies)) reachable
at `http://localhost:4444`.

### Configuration

| Variable | Required | Where |
|---|---|---|
| `NOTO_API_KEY` | yes | environment, or `~/.noto.env` |
| `NOTO_SERVER_URL` | no | same; the Stickies server, default `http://localhost:4444` |
| `NOTO_PUSHER_KEY` | no | same; the server's public Pusher key, turns on live updates |
| `NOTO_PUSHER_CLUSTER` | no | same; the server's Pusher cluster, e.g. `us2` |

A missing key shows a setup message rather than crashing. Without the Pusher
values the app works exactly the same, it just does not update on its own.

## Design

**Read-mostly on purpose.** It writes exactly twice: a new plain-text note, and
moving a note to TRASH.
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
Sources/Noto/
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

---

<div align="center">

<a href="https://bunlongheng.com"><img src="https://img.shields.io/badge/-bunlongheng.com-3A3A3C?style=for-the-badge&amp;labelColor=2A2A2C&amp;logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAcCAMAAABF0y%2BmAAADAFBMVEXx8vLq6v%2F19fX09PT8%2Ff309PT5%2BfnAwMBMaXHx8vL19fX5%2Bfny8vL09PT39%2Ff6%2Bfn6%2Bvr09PTx8fH4%2BPn%2F8vLy8%2FP09PTz8%2FPy8vL%2F%2F%2F%2Fz9PTz9PP19fby8vP19PXz8%2FT19%2Fb08%2FTx8vLy8vL09vby8%2FL29vf19fTv8PDz9vb7%2Bvn%2F%2Ff%2F9%2Ff3w8vH29fb%2F%2FP339%2Ff5%2Bfn59%2Ff19PT09PR7rao3VF3%2F%2Fv8AKDR6sqsBV1vv8fL4%2BPiux8b8%2Bvq90NDy8%2FR%2BlpppnZyZqrACLTxclZJSkI9en5ssZ2luqaUAeWgqbW4BX1gCfG0%2Fa3QaVG0MN0UKNUKUpKsGpYMAKjoRQ1UDf3AQRloJqIgEm32d0cUBg3ElbnQIln8eVWgrmIdP0KzF5d5s2acdfHwppJCP5MMXl4Tz8%2FLv8%2FP39%2FiewL5%2BqahYf4IrTFZkk5KlxsREiIYAHiqDnKFmnJowc3IdVllvpKK7zc3D2tnk5%2BmuycdwpKKuub2yv8Ly%2B%2FkAMT7z%2Bvjq7e09gH93q6kGdWpGgoJZmJSlw8M7c3WwyceTw76w1M8mYmpFfX8lW2AFOEpGiYhxqqRrqaRb2rdIsZ8AVE91jpU7d3t3saqBoKhako4AWVEcUlg3aWwDupAHb2YwmIkPP1ERSVA7WmZ8tq8HT14oZW%2BYuLsMl3wQT10ROksENUc8Z3MJSGVLh4dqpJ%2BXr7U51awUgHM4v6ad1MkPuJZAiowVd3IEhnZH0aoYrI05p5sDtYwkzZ8EPViYxsRel5USbHAIgmwIM0gQamzU4uF2malQi4oWQFQ1zaYrp4UXlYwfiHoyxqFE1q4qeX4yn5JIxKkdrX1b1rAbWGvd5Oh91sRijpomsJEVc3Ukc34dqIcwuJVKwZIXkoQZcXlNv5g%2BqZUZvpNl2rPG9N0WkIoNqouW4sVPwp%2BM0b6h0ssfq4d%2F1r8hpo%2Fh9e4AamUjnI9avaBixqgklYWSwL4xtItUxplYl5qZ58mq78wMgnYXfnlOmJaR1L%2Bj78ny9fS%2FrXQPAAAAFXRSTlP7Brvx%2FsJhAgD87r4U72C4uGH8vhRDodYHAAAACXBIWXMAAAsTAAALEwEAmpwYAAAC6UlEQVQokS2Sd3BUVRSHb0KS3QRCiZw5t%2By9j33zXjZkyUs2uekhEAi9dwRCL4JUEQRFAQUs9A4WOopKU0GpFoqCBZUivaqoFKkWLIS5GX7%2FfnPO78yZj%2Fj8UTViK6HggvNgSGuluEZRKbZqlN9H%2FFWiWUzIFQK5fhjOIRTDoqv4ia86S4q3KSByHdSqIhxofBKr5iNxLMm2bQqWVkorJ%2BAkO46nkQJhceSRmCTDvKJIJBLJzMxMLU6POJ4eBPF1KpNEbdt2Cms4LCcnZ%2FX6D3d%2BsKJJ7VSlNLoqgbjUtmkKKxlVmpf3bsFXW3d1b77gueJAQIPQBCilkMKemNi23Ts9T35%2FaMe2rsvmTypylGUFCSIYWJLXrm2nUwOPfNO5w%2B73Okxnjqe0JigQEL3JizoeONr%2F2u99vju4fd1rdZnyspQmnGvAUBprWNqz348%2FhXN%2F6P1%2By4Uvs%2FJkpRQRwpJBRVn7vf16Dfitz5XevQqWt3yalXtKaRIUQmglWfsu5y7%2BMrDs0TMftWo1ZVy64xioOVpcIdt8%2Fvqvf9%2F859KJsrLmrzA%2BOKC0IkFEtJza7JOfr%2FYd0P9G98tdOxe0Hp9qJrOIBgDuOeEtp%2F%2B4d%2FvWX%2F%2F9u%2B%2FtlaUTmOWZg7SQEEyuFe52%2BML9O3cZO%2F5xl06zn2VcadOJUqJTzt7a82XfP7sx9vmGNm1m1MstV4IHCVAAoTLqL1372ddn%2Fz%2B2v%2FWq12c1fSpsaeQWAZAANntxzuI3e3zbo8XGpm%2FMnNqiXrh%2BljaPd6UUabkjps19tdGnX2zKb9b4pTFDCzOMLmYtpW5h%2BpCRTeYtyV%2BT36zx808OL4xYGoFrkqDTbJpSXLdRgwbPZL%2BQnT129OOPFVEEsAMJpHKdeKMJgJSAiALdjJANQKnRJI4R6boAKEwLCiGoBBegQjBftQo1KQWOlplFKSV9qGaF1NpAE7QQESTlMSy6pp%2F4%2FFFVYxMNRBTaiM0tkImxNaL8vgfDR8gvoYRaxgAAAABJRU5ErkJggg%3D%3D" alt="bunlongheng.com"></a>
<a href="https://www.linkedin.com/in/bunlongheng/"><img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white" alt="LinkedIn"></a>
<a href="https://www.instagram.com/ibunlong/"><img src="https://img.shields.io/badge/Instagram-C13584?style=for-the-badge&logo=instagram&logoColor=white" alt="Instagram"></a>
<a href="mailto:bheng.code@gmail.com"><img src="https://img.shields.io/badge/Email-2E7D32?style=for-the-badge&logo=gmail&logoColor=white" alt="Email"></a>

<br>

Built by **[Bunlong](https://bunlongheng.com)** &nbsp;&middot;&nbsp; [more apps](https://bunlongheng.com/projects)

</div>
