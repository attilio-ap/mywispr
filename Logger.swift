import Foundation

/// Lightweight diagnostic logger.
///
/// **Privacy note.** MyWispr handles dictated text that may contain passwords,
/// private messages or client data. Two rules follow from that:
///
/// 1. Transcript contents are logged *only* when the user explicitly opts into
///    verbose logging. Otherwise `logSensitive` records the length of the text
///    and nothing else, which is enough to debug the pipeline without ever
///    persisting what was said.
/// 2. The log lives in the user-owned `~/Library/Logs/MyWispr/` directory, not
///    in the world-readable `/tmp`, and is capped so it cannot grow unbounded.
///
/// Writes are dispatched to a serial background queue: the keyboard event tap
/// runs on a `.userInteractive` thread inside the system event path, and must
/// never block on disk I/O.
enum Logger {

    /// UserDefaults key backing the "verbose logging" toggle in the dashboard.
    static let verboseDefaultsKey = "mw_verbose_logging"

    /// Maximum log size before it is rotated to `mywispr.log.1`.
    private static let maxLogBytes = 1_000_000

    private static let queue = DispatchQueue(label: "com.attilio.mywispr.logger", qos: .utility)

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// `~/Library/Logs/MyWispr/mywispr.log`, falling back to a temporary directory
    /// if the Logs directory cannot be created.
    static let logURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/MyWispr", isDirectory: true)

        if let base {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("mywispr.log")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mywispr.log")
    }()

    /// Whether transcript contents may be written to disk.
    /// Off by default; opt in from Dashboard → Impostazioni, or with
    /// `defaults write com.attilio.MyWispr mw_verbose_logging -bool YES`.
    static var isVerbose: Bool {
        UserDefaults.standard.bool(forKey: verboseDefaultsKey)
    }

    /// Logs a diagnostic message that is known not to contain dictated text.
    static func log(_ message: String) {
        write(message)
    }

    /// Logs a message that embeds dictated text.
    ///
    /// When verbose logging is off, only the character count is recorded, so the
    /// log still shows what the pipeline did without revealing what was said.
    ///
    /// - Parameters:
    ///   - label: Stage description, e.g. `"Final transcript"`.
    ///   - text: The sensitive text itself.
    static func logSensitive(_ label: String, _ text: String) {
        if isVerbose {
            write("\(label): \(text)")
        } else {
            write("\(label): <\(text.count) chars redacted>")
        }
    }

    /// Empties the log file.
    static func clear() {
        queue.async {
            try? Data().write(to: logURL)
        }
    }

    // MARK: - Internals

    private static func write(_ message: String) {
        #if DEBUG
        print(message)
        #endif

        queue.async {
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            rotateIfNeeded()

            let fm = FileManager.default
            if fm.fileExists(atPath: logURL.path), let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // If the log itself cannot be written there is nothing useful to do.
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Rotates the log once it exceeds `maxLogBytes`, keeping a single backup.
    /// Must be called on `queue`.
    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? Int, size > maxLogBytes else { return }

        let backup = logURL.appendingPathExtension("1")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: logURL, to: backup)
    }
}
