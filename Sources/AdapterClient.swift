import Foundation

/// Talks to the bundled mediaremote-adapter through `/usr/bin/perl`.
///
/// `perl` is Apple-signed, entitled to use MediaRemote, and (unlike `osascript`)
/// not library-validated, so it can `DynaLoader`-load the vendored
/// `MediaRemoteAdapter.framework`. That yields reliable, always-warm now-playing
/// data (via notifications) plus real playback control — no Accessibility
/// permission required. This is the ungive/mediaremote-adapter technique.
final class AdapterClient {
    /// MediaRemote command IDs.
    enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
        case toggleShuffle = 6
        case toggleRepeat = 7
    }

    private let perl = "/usr/bin/perl"
    private let scriptPath: String
    private let frameworkPath: String
    private let onPayload: ([String: Any]) -> Void

    private var streamProcess: Process?
    private var buffer = Data()
    private var stopped = false

    /// Fails to initialize if the adapter isn't bundled where expected.
    init?(onPayload: @escaping ([String: Any]) -> Void) {
        guard let resources = Bundle.main.resourcePath else { return nil }
        scriptPath = resources + "/mediaremote-adapter.pl"
        frameworkPath = resources + "/MediaRemoteAdapter.framework"
        self.onPayload = onPayload
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptPath), fm.fileExists(atPath: frameworkPath) else {
            return nil
        }
    }

    // MARK: - Streaming

    func startStream() {
        stopped = false
        launch()
    }

    func stop() {
        stopped = true
        streamProcess?.terminate()
        streamProcess = nil
    }

    private func launch() {
        buffer.removeAll(keepingCapacity: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: perl)
        process.arguments = [
            scriptPath, frameworkPath,
            "stream", "--no-diff", "--debounce=200",
        ]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        process.terminationHandler = { [weak self] _ in
            guard let self, !self.stopped else { return }
            // The adapter shouldn't exit; if it does, restart it after a beat.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                guard !self.stopped else { return }
                self.launch()
            }
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            NSLog("TidalMiniPlayer: failed to launch adapter: \(error)")
        }
    }

    /// Splits the stream into complete newline-delimited JSON messages.
    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard
                !line.isEmpty,
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                object["type"] as? String == "data",
                let payload = object["payload"] as? [String: Any]
            else { continue }
            onPayload(payload)
        }
    }

    // MARK: - Control

    func send(_ command: Command) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: perl)
        process.arguments = [scriptPath, frameworkPath, "send", String(command.rawValue)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
