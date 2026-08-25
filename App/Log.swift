import Foundation
import os

/// Registro de la app.
///
/// Va siempre al log unificado (`log stream --predicate
/// 'subsystem == "app.schoolaid.Parla"'`) y, si se lanza con
/// `PARLA_STDERR_LOG=1`, también a stderr — útil cuando el log unificado no es
/// accesible o cuando se ejecuta la app desde la terminal.
struct Log: Sendable {
    private let logger: Logger
    private let category: String

    private static let mirrorToStderr =
        ProcessInfo.processInfo.environment["PARLA_STDERR_LOG"] == "1"

    private init(_ category: String) {
        self.category = category
        self.logger = Logger(subsystem: "app.schoolaid.Parla", category: category)
    }

    static let speech = Log("speech")
    static let audio = Log("audio")
    static let pipeline = Log("pipeline")

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        mirror("INFO", message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        mirror("ERROR", message)
    }

    private func mirror(_ level: String, _ message: String) {
        guard Self.mirrorToStderr else { return }
        FileHandle.standardError.write(Data("[\(category)] \(level): \(message)\n".utf8))
    }
}
