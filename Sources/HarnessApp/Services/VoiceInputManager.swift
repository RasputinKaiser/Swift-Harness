import Foundation
import AVFoundation
import Speech
import Observation

/// Hold-to-talk voice input manager.
/// Uses SFSpeechRecognizer for on-device speech recognition and
/// AVAudioEngine for microphone capture.
/// Transcribed text is sent directly to the NCodeBridge.
@Observable
final class VoiceInputManager {

    private(set) var isRecording = false
    private(set) var partialTranscription: String = ""
    private(set) var lastError: String?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    /// Request speech recognition authorization.
    /// Returns true if authorized.
    @MainActor
    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        if status != .authorized {
            lastError = "Speech recognition not authorized (status: \(status.rawValue))"
            return false
        }

        let audioStatus = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        if !audioStatus {
            lastError = "Microphone access denied"
            return false
        }

        speechRecognizer = SFSpeechRecognizer()
        if speechRecognizer == nil {
            lastError = "SFSpeechRecognizer unavailable"
            return false
        }
        return true
    }

    @MainActor
    func startRecording() {
        guard !isRecording else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            lastError = "Speech recognizer not available"
            return
        }

        // Stop any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        partialTranscription = ""

        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // Configure audio session
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            lastError = "Audio engine start failed: \(error.localizedDescription)"
            return
        }

        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result = result {
                    self.partialTranscription = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }
        }
    }

    @MainActor
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    @MainActor
    func finalizeTranscription() -> String {
        let text = partialTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        partialTranscription = ""
        return text
    }

    /// Clean up on deinit
    deinit {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
    }
}