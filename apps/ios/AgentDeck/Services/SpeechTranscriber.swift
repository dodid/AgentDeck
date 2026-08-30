import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriber {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var onUpdate: ((String) -> Void)?
    private var onCompletion: ((Result<Void, Error>) -> Void)?
    private var isFinishing = false

    init(locale: Locale = .autoupdatingCurrent) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    func start(
        onUpdate: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) async throws {
        stop(notify: false)

        speechRecognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent)
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechTranscriberError.unavailable
        }
        guard await requestSpeechAccess() else {
            throw SpeechTranscriberError.speechPermissionDenied
        }
        guard await requestMicrophoneAccess() else {
            throw SpeechTranscriberError.microphonePermissionDenied
        }

        self.onUpdate = onUpdate
        self.onCompletion = onCompletion

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.addsPunctuation = true
            self.recognitionRequest = recognitionRequest

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let format = preferredRecordingFormat(for: inputNode)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let transcript = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.onUpdate?(transcript)
                        if result.isFinal {
                            self.finish(with: .success(()))
                        }
                    }
                }

                if let error {
                    Task { @MainActor in
                        self.finish(with: .failure(error))
                    }
                }
            }
        } catch {
            stop(notify: false)
            throw error
        }
    }

    func stop(notify: Bool = true) {
        tearDownAudioPipeline()

        guard notify else {
            onUpdate = nil
            onCompletion = nil
            return
        }

        finish(with: .success(()))
    }

    private func finish(with result: Result<Void, Error>) {
        guard !isFinishing else { return }
        isFinishing = true

        tearDownAudioPipeline()

        let completion = onCompletion
        onUpdate = nil
        onCompletion = nil
        isFinishing = false
        completion?(result)
    }

    private func tearDownAudioPipeline() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func preferredRecordingFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat? {
        let outputFormat = inputNode.outputFormat(forBus: 0)
        if outputFormat.isValidRecordingFormat {
            return outputFormat
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        if inputFormat.isValidRecordingFormat {
            return inputFormat
        }

        return nil
    }

    private func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private extension AVAudioFormat {
    var isValidRecordingFormat: Bool {
        sampleRate > 0 && channelCount > 0
    }
}

enum SpeechTranscriberError: LocalizedError {
    case unavailable
    case microphonePermissionDenied
    case speechPermissionDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "Speech recognition is currently unavailable.")
        case .microphonePermissionDenied:
            return String(localized: "Microphone access is required to dictate messages.")
        case .speechPermissionDenied:
            return String(localized: "Speech recognition access is required to dictate messages.")
        }
    }
}