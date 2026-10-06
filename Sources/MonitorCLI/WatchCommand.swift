import ArgumentParser
import Darwin
import Foundation
import MonitorCore
import MonitorRuntime

extension MonitorCommand {
    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Watch a JSONL directory with FSEvents and emit JSON status lines.",
            discussion: "SIGUSR1 pauses, SIGUSR2 resumes with reconciliation; SIGINT/SIGTERM stop gracefully. "
                + "With --alerts, alert transitions are emitted as {\"alert\": ...} lines after each import."
        )
        @OptionGroup var options: DatabaseOptions
        @Argument(help: "Source directory, recursively watched. Sources remain read only.") var path: String
        @Option(help: "Bounded event coalescing window in milliseconds (1...60000).")
        var debounceMilliseconds = 250
        @Flag(help: "Evaluate existing analytics after each import and emit alert transition lines.")
        var alerts = false

        mutating func validate() throws {
            guard (1...60_000).contains(debounceMilliseconds) else {
                throw ValidationError("--debounce-milliseconds must be between 1 and 60000.")
            }
        }

        mutating func run() async throws {
            let monitor = try options.runtime()
            let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let timing = WatchOptions(debounce: .milliseconds(debounceMilliseconds))
            let writer = try WatchOutput()
            let watch = try await monitor.watch(root, options: timing)
            let watchdog = alerts ? AlertWatchdog(
                monitor: monitor, center: AlertCenter(monitor: monitor, sinks: [AlertLineSink(writer: writer)])
            ) : nil
            let signals = WatchSignals { number in
                Task {
                    switch number {
                    case SIGUSR1: await watch.pause()
                    case SIGUSR2: await watch.resume()
                    default: await watch.stop()
                    }
                }
            }
            defer { signals.cancel() }
            let output = Task {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    for await status in watch.updates {
                        var line = try encoder.encode(status)
                        line.append(10)
                        try await writer.write(line)
                        // An alert evaluation failure must not stop the watch; it is reported on stderr.
                        do { try await watchdog?.handle(status, root: root) } catch {
                            FileHandle.standardError.write(Data("alert evaluation failed: \(error)\n".utf8))
                        }
                    }
                } catch {
                    await watch.stop()
                    throw error
                }
            }
            await watch.waitUntilStopped()
            let deadline = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { output.cancel() }
            }
            defer { deadline.cancel() }
            do { try await output.value } catch is CancellationError { /* Drop backpressured output on shutdown. */ }
        }
    }
}

/// Writes alert transitions on the watch output as `{"alert": event}` lines, next to status lines.
struct AlertLineSink: AlertSink {
    private struct Line: Encodable { let alert: AlertEvent }
    let writer: WatchOutput

    func deliver(_ events: [AlertEvent]) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        for event in events {
            guard var line = try? encoder.encode(Line(alert: event)) else { continue }
            line.append(10)
            try? await writer.write(line)
        }
    }
}

/// Nonblocking pipe writes keep a slow consumer from preventing signal-driven shutdown.
final class WatchOutput: Sendable {
    private let previousFlags: Int32

    init() throws {
        previousFlags = fcntl(STDOUT_FILENO, F_GETFL)
        guard previousFlags >= 0, fcntl(STDOUT_FILENO, F_SETFL, previousFlags | O_NONBLOCK) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func write(_ data: Data) async throws {
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let (written, code) = data.withUnsafeBytes { bytes in
                (Darwin.write(STDOUT_FILENO, bytes.baseAddress?.advanced(by: offset), data.count - offset), errno)
            }
            if written > 0 {
                offset += written
            } else if written < 0, code == EINTR {
                continue
            } else if written < 0, code == EAGAIN || code == EWOULDBLOCK {
                try await Task.sleep(for: .milliseconds(20))
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        }
    }

    deinit { _ = fcntl(STDOUT_FILENO, F_SETFL, previousFlags) }
}

/// CLI-only signal dispositions; restored after the event sources are cancelled.
final class WatchSignals {
    private var sources: [DispatchSourceSignal] = []
    private var previous: [(Int32, sig_t?)] = []

    init(receive: @escaping @Sendable (Int32) -> Void) {
        let queue = DispatchQueue(label: "SessionMonitor.Signals")
        for number in [SIGINT, SIGTERM, SIGUSR1, SIGUSR2, SIGPIPE] {
            previous.append((number, signal(number, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { receive(number) }
            sources.append(source)
            source.resume()
        }
    }

    func cancel() {
        for source in sources { source.cancel() }
        sources.removeAll()
        for (number, handler) in previous { signal(number, handler) }
        previous.removeAll()
    }

    deinit { cancel() }
}
