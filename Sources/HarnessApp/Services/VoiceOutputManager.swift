import Foundation
import AVFoundation
import Observation

/// Voice output manager — reads assistant responses aloud via AVSpeechSynthesizer.
/// Companion to VoiceInputManager (which captures speech-to-text on input).
///
/// Two ways to use:
/// - `isAutoSpeakOn`: when true, every new assistant text block is enqueued
///   for synthesis automatically.
/// - `speak(text:)`: one-shot synthesis of arbitrary text.
///
/// Synthesis is cancelled on `stop()` and on deinit.
@Observable
final class VoiceOutputManager: NSObject, AVSpeechSynthesizerDelegate {

    private(set) var isSpeaking = false
    private(set) var isAutoSpeakOn = false
    private(set) var lastSpokenSnip: String?
    private(set) var lastError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingText: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    deinit {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Public

    @MainActor
    func toggleAutoSpeak() {
        isAutoSpeakOn.toggle()
        if !isAutoSpeakOn {
            stop()
        }
    }

    @MainActor
    func speak(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1

        // If currently speaking, queue the new utterance (AVSpeechSynthesizer does this)
        synthesizer.speak(utterance)
        lastSpokenSnip = String(trimmed.prefix(80))
    }

    @MainActor
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if isSpeaking { isSpeaking = false }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didPause utterance: AVSpeechUtterance) {
        // No-op for now — pause/resume could be added later if needed
    }
}