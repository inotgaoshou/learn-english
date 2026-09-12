import AVFoundation
import Foundation

enum SpeechAccent: String, CaseIterable, Identifiable {
    case american
    case british

    var id: String { rawValue }

    var title: String {
        switch self {
        case .american:
            return "美式"
        case .british:
            return "英式"
        }
    }

    var languageCode: String {
        switch self {
        case .american:
            return "en-US"
        case .british:
            return "en-GB"
        }
    }
}

final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private var synthesizer = AVSpeechSynthesizer()
    private var pendingUtterances: [AVSpeechUtterance] = []
    private var playbackGeneration = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Float, repetitions: Int, accent: SpeechAccent = .american) {
        let cleanText = WordTextNormalizer.displayText(for: text)
        guard !cleanText.isEmpty else {
            return
        }

        configureAudioSessionForSpeech()
        playbackGeneration += 1
        let generation = playbackGeneration
        let wasActive = synthesizer.isSpeaking || synthesizer.isPaused
        prepareSynthesizerForReplacement()

        let repeatCount = max(1, repetitions)
        pendingUtterances = (0..<repeatCount).map { _ in
            let utterance = AVSpeechUtterance(string: cleanText)
            utterance.voice = AVSpeechSynthesisVoice(language: accent.languageCode) ?? AVSpeechSynthesisVoice(language: "en")
            utterance.rate = rate
            utterance.volume = 1.0
            utterance.postUtteranceDelay = 0.35
            return utterance
        }

        if wasActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.playbackGeneration == generation else {
                    return
                }
                self.speakNextUtterance(for: generation)
            }
        } else {
            speakNextUtterance(for: generation)
        }
    }

    func pauseOrContinue() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        } else if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    func stop() {
        playbackGeneration += 1
        pendingUtterances.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard synthesizer === self.synthesizer else {
            return
        }
        speakNextUtterance(for: playbackGeneration)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard synthesizer === self.synthesizer else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if !self.synthesizer.isSpeaking && self.pendingUtterances.isEmpty {
                self.isSpeaking = false
                self.isPaused = false
            }
        }
    }

    private func speakNextUtterance(for generation: Int) {
        guard generation == playbackGeneration else {
            return
        }

        guard !pendingUtterances.isEmpty else {
            isSpeaking = false
            isPaused = false
            return
        }

        let next = pendingUtterances.removeFirst()
        isSpeaking = true
        isPaused = false
        synthesizer.speak(next)
    }

    private func prepareSynthesizerForReplacement() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        isSpeaking = false
        isPaused = false
    }

    private func configureAudioSessionForSpeech() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure speech audio session: \(error)")
        }
        #endif
    }
}
