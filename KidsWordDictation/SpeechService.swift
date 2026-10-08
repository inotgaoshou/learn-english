import AVFoundation
import Foundation

enum SpeechAccent: String, CaseIterable, Identifiable {
    case american
    case british

    static let storageKey = "KidsWordDictation.speechAccent"

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
    @Published private(set) var activeSequenceIndex: Int?

    private var synthesizer = AVSpeechSynthesizer()
    private var pendingUtterances: [AVSpeechUtterance] = []
    private var utteranceIndices: [ObjectIdentifier: Int] = [:]
    private var playbackCompletion: (generation: Int, action: () -> Void)?
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

        let repeatCount = max(1, repetitions)
        let utterances = (0..<repeatCount).map { _ in
            makeUtterance(text: cleanText, rate: rate, accent: accent, delay: 0.35)
        }
        play(utterances)
    }

    func speakSequence(_ texts: [String], rate: Float, repetitions: Int = 1, accent: SpeechAccent = .american) {
        let cleanTexts = texts
            .map { WordTextNormalizer.displayText(for: $0) }
            .filter { !$0.isEmpty }
        guard !cleanTexts.isEmpty else {
            return
        }

        let repeatCount = max(1, repetitions)
        let utterances = (0..<repeatCount).flatMap { _ in
            cleanTexts.map { text in
                makeUtterance(text: text, rate: rate, accent: accent, delay: 0.55)
            }
        }
        play(utterances)
    }

    func speakIPA(_ ipa: String, accent: SpeechAccent = .american, rate: Float = 0.38) {
        let cleanIPA = normalizedIPA(ipa)
        guard !cleanIPA.isEmpty else {
            return
        }
        play([makeIPAUtterance(ipa: cleanIPA, rate: rate, accent: accent, delay: 0.2)])
    }

    func speakIPASequence(
        _ ipaSegments: [String],
        accent: SpeechAccent = .american,
        rate: Float = 0.36,
        completion: (() -> Void)? = nil
    ) {
        let utterances = ipaSegments
            .map(normalizedIPA)
            .filter { !$0.isEmpty }
            .map { makeIPAUtterance(ipa: $0, rate: rate, accent: accent, delay: 0.28) }
        guard !utterances.isEmpty else {
            return
        }
        play(utterances, tracksSequence: true, completion: completion)
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
        utteranceIndices.removeAll()
        playbackCompletion = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        activeSequenceIndex = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard synthesizer === self.synthesizer else {
            return
        }
        activeSequenceIndex = utteranceIndices[ObjectIdentifier(utterance)]
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
            activeSequenceIndex = nil
            utteranceIndices.removeAll()
            let completion = playbackCompletion
            playbackCompletion = nil
            if completion?.generation == generation {
                completion?.action()
            }
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
        activeSequenceIndex = nil
    }

    private func play(
        _ utterances: [AVSpeechUtterance],
        tracksSequence: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        configureAudioSessionForSpeech()
        playbackGeneration += 1
        let generation = playbackGeneration
        let wasActive = synthesizer.isSpeaking || synthesizer.isPaused
        prepareSynthesizerForReplacement()
        pendingUtterances = utterances
        utteranceIndices = tracksSequence
            ? Dictionary(uniqueKeysWithValues: utterances.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })
            : [:]
        playbackCompletion = completion.map { (generation, $0) }

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

    private func makeUtterance(text: String, rate: Float, accent: SpeechAccent, delay: TimeInterval) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.languageCode) ?? AVSpeechSynthesisVoice(language: "en")
        utterance.rate = rate
        utterance.volume = 1.0
        utterance.postUtteranceDelay = delay
        return utterance
    }

    private func makeIPAUtterance(ipa: String, rate: Float, accent: SpeechAccent, delay: TimeInterval) -> AVSpeechUtterance {
        let attributedText = NSMutableAttributedString(string: "sound")
        attributedText.addAttribute(
            NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute),
            value: ipa,
            range: NSRange(location: 0, length: attributedText.length)
        )
        let utterance = AVSpeechUtterance(attributedString: attributedText)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.languageCode) ?? AVSpeechSynthesisVoice(language: "en")
        utterance.rate = rate
        utterance.volume = 1.0
        utterance.postUtteranceDelay = delay
        return utterance
    }

    private func normalizedIPA(_ ipa: String) -> String {
        WordTextNormalizer.displayText(for: ipa)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/[]"))
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
