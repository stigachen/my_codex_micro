import Foundation
import os

/// Tiny logger: stderr when run from a terminal, plus ~/Library/Logs/MicroKeys.log.
enum Log {
    private static let logger = Logger(subsystem: "com.chenguang.MicroKeys", category: "app")
    private static let queue = DispatchQueue(label: "microkeys.log")
    private static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        return dir.appendingPathComponent("MicroKeys.log")
    }()
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) { write("INFO", message); logger.info("\(message, privacy: .public)") }
    static func warn(_ message: String) { write("WARN", message); logger.warning("\(message, privacy: .public)") }
    static func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .public)") }

    private static func write(_ level: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) [\(level)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
                return
            }
            defer { try? handle.close() }
            if let size = try? handle.seekToEnd(), size > 2_000_000 {
                try? handle.truncate(atOffset: 0)
            }
            handle.write(Data(line.utf8))
        }
    }
}
