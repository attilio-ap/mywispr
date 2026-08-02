import Foundation

/// Minimal assertion helpers shared by the test suites.
///
/// Deliberately dependency-free. MyWispr builds with plain `swiftc` and has no
/// package manifest, so XCTest is not available without restructuring the
/// project around SwiftPM — which would be a large change to buy very little
/// for a handful of pure-logic suites.
enum T {

    static var failures = 0
    static var checks = 0

    /// Asserts two strings are equal, printing both on failure.
    static func equal(_ label: String, _ got: String, _ want: String) {
        checks += 1
        if got == want {
            print("  PASS  \(label)  ->  \(got)")
        } else {
            failures += 1
            print("  FAIL  \(label)")
            print("        got:  \(got)")
            print("        want: \(want)")
        }
    }

    static func equal(_ label: String, _ got: Int, _ want: Int) {
        equal(label, "\(got)", "\(want)")
    }

    /// Asserts a double to two decimal places, avoiding float formatting noise.
    static func equal(_ label: String, _ got: Double, _ want: Double) {
        equal(label, String(format: "%.2f", got), String(format: "%.2f", want))
    }

    static func section(_ title: String) {
        print("\n== \(title) ==")
    }

    /// Prints the tally and exits with a status the shell can act on.
    static func finish(_ suite: String) -> Never {
        if failures == 0 {
            print("\n\(suite): ALL PASS (\(checks) checks)")
            exit(0)
        }
        print("\n\(suite): \(failures) FAILURE(S) out of \(checks) checks")
        exit(1)
    }
}
