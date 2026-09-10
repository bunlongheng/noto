import Foundation

/// Minimal assertion harness.
///
/// SwiftPM cannot run on the CommandLineTools-only toolchain this project builds
/// with (`swift build` fails to link the manifest), so XCTest and swift-testing are
/// both unavailable. This gives the same guarantee with zero dependencies: it runs
/// identically from ./test.sh locally and in CI, and exits non-zero on any failure.
enum T {
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var failures: [String] = []

    static func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            passed += 1
        } else {
            let extra = detail()
            failures.append(extra.isEmpty ? name : "\(name) - \(extra)")
        }
    }

    static func equal<V: Equatable>(_ name: String, _ actual: V, _ expected: V) {
        check(name, actual == expected, "got \(actual), expected \(expected)")
    }

    static func report() -> Never {
        for f in failures { FileHandle.standardError.write(Data("FAIL  \(f)\n".utf8)) }
        let total = passed + failures.count
        print("\n\(passed)/\(total) passed" + (failures.isEmpty ? "" : ", \(failures.count) FAILED"))
        exit(failures.isEmpty ? 0 : 1)
    }
}
