import Foundation

/// Suggestions for the folder picker only; never grants access or starts an import.
enum RolloutDirectorySelection {
    /// Codex names folders with Gregorian years, regardless of the user's preferred calendar.
    static func directoryYear(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.component(.year, from: date)
    }

    static func initialDirectory(
        preferred: URL?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        year: Int = directoryYear(),
        fileManager: FileManager = .default
    ) -> URL {
        let codex = home.appending(path: ".codex", directoryHint: .isDirectory)
        let sessions = codex.appending(path: "sessions", directoryHint: .isDirectory)
        let candidates = [preferred, sessions.appending(path: String(year), directoryHint: .isDirectory),
                          sessions, codex, home].compactMap { $0 }
        return candidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        } ?? home
    }
}
