import Darwin
import Foundation

// MARK: - IsolatedDefaultsSuite

/// Creates a throwaway `UserDefaults` suite for a test and keeps `~/Library/Preferences` from
/// filling up with one plist per test run. `UserDefaults(suiteName:)` writes
/// `<suite>.plist` there and `removePersistentDomain` empties the domain without deleting the
/// file, so suites are named `<prefix>.<pid>.<uuid>`: the first use in a process sweeps
/// files left by processes that are no longer running (test workers are not guaranteed to
/// run exit hooks), and the process's own files are removed at exit when that hook does run.
enum IsolatedDefaultsSuite {
    static func make(prefix: String) -> UserDefaults {
        sweepStaleSuites(prefix: prefix)
        let suiteName = "\(prefix).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        register(suiteName)
        return defaults
    }

    // MARK: Private

    private static let lock = NSLock()
    private static var suiteNames: Set<String> = []
    private static var sweptPrefixes: Set<String> = []
    private static var exitHookInstalled = false

    private static var preferencesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    private static func register(_ suiteName: String) {
        lock.lock()
        suiteNames.insert(suiteName)
        if !exitHookInstalled {
            exitHookInstalled = true
            atexit {
                IsolatedDefaultsSuite.removeOwnSuites()
            }
        }
        lock.unlock()
    }

    /// Deletes `<prefix>.<pid>.<uuid>.plist` files whose owning process has exited.
    private static func sweepStaleSuites(prefix: String) {
        lock.lock()
        let alreadySwept = !sweptPrefixes.insert(prefix).inserted
        lock.unlock()
        guard !alreadySwept else {
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: preferencesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix("\(prefix).") {
            let remainder = entry.lastPathComponent.dropFirst(prefix.count + 1)
            guard let pidText = remainder.split(separator: ".").first,
                  let pid = Int32(pidText),
                  pid != ownPID,
                  kill(pid, 0) != 0
            else {
                continue
            }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func removeOwnSuites() {
        lock.lock()
        let names = suiteNames
        suiteNames.removeAll()
        lock.unlock()

        for name in names {
            // Flush any pending write first; emptying the domain here would only make cfprefsd
            // rewrite an empty plist after the file is gone.
            UserDefaults(suiteName: name)?.synchronize()
            try? FileManager.default.removeItem(at: preferencesDirectory.appendingPathComponent("\(name).plist"))
        }
    }
}
