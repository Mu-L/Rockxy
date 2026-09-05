import Foundation
@testable import Rockxy
import Testing

struct BoundedHelperCommandTests {
    // MARK: Internal

    @Test("command exit status and bounded stderr are preserved")
    func preservesFailure() throws {
        let result = try BoundedHelperCommand.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'fixture failure' >&2; exit 7"], timeout: 2
        )
        #expect(result.status == 7)
        #expect(String(data: result.diagnostic, encoding: .utf8) == "fixture failure")
    }

    @Test("stdout never contaminates the bounded diagnostic")
    func stdoutIsDiscarded() throws {
        let result = try BoundedHelperCommand.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'to stdout'; printf 'to stderr' >&2; exit 0"], timeout: 2
        )
        #expect(result.status == 0)
        #expect(String(data: result.diagnostic, encoding: .utf8) == "to stderr")
    }

    @Test("a noisy command cannot fill its pipe and deadlock the helper")
    func drainsBoundedOutput() throws {
        let result = try BoundedHelperCommand.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do printf 'fixture output line\\n' >&2; i=$((i+1)); done"],
            timeout: 5
        )
        #expect(result.status == 0)
        #expect(result.diagnostic.count == 4_096)
    }

    @Test("a diagnostic that is not valid UTF-8 keeps its readable text")
    func preservesUndecodableDiagnostic() throws {
        // A bounded copy of stderr can end mid-character: \342\230 is a truncated U+2603. A strict
        // decode returns nil for the whole thing, which is why the helper decodes leniently.
        let result = try BoundedHelperCommand.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'fixture \\342\\230' >&2; exit 3"], timeout: 2
        )
        #expect(result.status == 3)
        #expect(String(data: result.diagnostic, encoding: .utf8) == nil)
        // swiftlint:disable:next optional_data_string_conversion
        let lenient = String(decoding: result.diagnostic, as: UTF8.self)
        #expect(lenient.hasPrefix("fixture "))
    }

    @Test(
        "a timeout outside the permitted range is rejected before anything is spawned",
        arguments: [0, -1, 31, TimeInterval.nan, .infinity]
    )
    func rejectsInvalidTimeout(timeout: TimeInterval) {
        #expect(throws: BoundedHelperCommand.Failure.invalidTimeout) {
            try BoundedHelperCommand.run(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"], timeout: timeout
            )
        }
    }

    @Test("a missing executable is reported as a spawn failure rather than a hang")
    func missingExecutableFailsToSpawn() {
        let failure = #expect(throws: BoundedHelperCommand.Failure.self) {
            try BoundedHelperCommand.run(
                executable: URL(fileURLWithPath: "/usr/bin/rockxy-nonexistent-fixture"),
                arguments: [], timeout: 2
            )
        }
        #expect(failure == .spawnFailed(ENOENT))
    }

    @Test("a child that ignores SIGTERM is gone by the time the runner returns")
    func timeoutEscalatesAndStopsTheChild() {
        // The marker is unique to this run, so what it records can only be this child.
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-bounded-\(UUID().uuidString).marker")
        defer { try? FileManager.default.removeItem(at: marker) }

        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: BoundedHelperCommand.Failure.timedOut) {
            try BoundedHelperCommand.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "trap '' TERM; while :; do printf x >> \"$0\"; sleep 0.05; done",
                    marker.path,
                ],
                timeout: 0.2
            )
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(elapsed < 3)

        // It really ran and really ignored SIGTERM, and it wrote nothing more after the return.
        let writtenAtReturn = Self.markerByteCount(marker)
        #expect(writtenAtReturn > 0)
        Thread.sleep(forTimeInterval: 0.4)
        #expect(Self.markerByteCount(marker) == writtenAtReturn)
    }

    // MARK: Private

    private static func markerByteCount(_ url: URL) -> Int {
        (try? Data(contentsOf: url).count) ?? 0
    }
}
