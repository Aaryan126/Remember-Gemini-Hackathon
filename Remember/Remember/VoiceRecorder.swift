import AVFAudio
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceRecorder: NSObject, @preconcurrency AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case recorded
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var timerTask: Task<Void, Never>?
    private var startedAt: Date?

    var isRecording: Bool { state == .recording }

    func start() async {
        guard state == .idle || state == .recorded else { return }
        discardRecording()
        state = .requestingPermission

        guard await Self.requestMicrophonePermission() else {
            state = .failed("Microphone access is required. Enable it in Settings > Privacy & Security > Microphone.")
            return
        }
        guard await Self.requestSpeechPermission() else {
            state = .failed("Speech Recognition access is required for the local transcript. Enable it in Settings > Privacy & Security > Speech Recognition.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            // The default mode is valid with every category. playAndRecord is
            // Apple's recommended category for apps that both capture and
            // later play audio, even when those operations are not simultaneous.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            guard session.isInputAvailable else {
                throw VoiceRecorderError.noAudioInput
            }
        } catch {
            state = .failed(Self.failureMessage(stage: "Audio session setup", error: error))
            try? session.setActive(false)
            return
        }

        do {
            let (recorder, url) = try makeRecorder()
            audioRecorder = recorder
            recordingURL = url
            elapsedTime = 0
            startedAt = Date()
            state = .recording
            startTimer()
        } catch {
            state = .failed(Self.failureMessage(stage: "Recorder setup", error: error))
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func stop() {
        guard state == .recording else { return }
        audioRecorder?.stop()
        audioRecorder = nil
        stopTimer()
        state = .recorded
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func discardRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        stopTimer()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        elapsedTime = 0
        startedAt = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func releaseRecordingAfterSave() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        state = .idle
        elapsedTime = 0
        startedAt = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard state == .recording else { return }
        stopTimer()
        audioRecorder = nil
        state = flag ? .recorded : .failed("The recording stopped unexpectedly.")
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopTimer() {
        if let startedAt {
            elapsedTime = Date().timeIntervalSince(startedAt)
        }
        timerTask?.cancel()
        timerTask = nil
    }

    private func makeRecorder() throws -> (AVAudioRecorder, URL) {
        // Use NSNumber-compatible value types. Passing UInt32/Int values for
        // format or sample rate can surface as SessionCore paramErr (-50) on
        // physical devices even though the same dictionary works in a simulator.
        let candidates: [(extension: String, settings: [String: Any])] = [
            (
                "m4a",
                [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100.0,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            ),
            (
                "caf",
                [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 44_100.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ]
            ),
        ]

        var lastError: Error = VoiceRecorderError.couldNotStart
        for candidate in candidates {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "RememberVoice-\(UUID().uuidString).\(candidate.extension)",
                isDirectory: false
            )
            do {
                let recorder = try AVAudioRecorder(url: url, settings: candidate.settings)
                recorder.delegate = self
                guard recorder.prepareToRecord(), recorder.record() else {
                    throw VoiceRecorderError.couldNotStart
                }
                return (recorder, url)
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: url)
            }
        }
        throw lastError
    }

    private static func failureMessage(stage: String, error: Error) -> String {
        let nsError = error as NSError
        return "\(stage) failed (\(nsError.code)). Close other audio apps and try again."
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}

nonisolated enum VoiceRecorderError: Error {
    case couldNotStart
    case noAudioInput
}
