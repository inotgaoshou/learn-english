import PhotosUI
import SwiftUI
import Translation
import VisionKit

struct ArticleTranslatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var translationError: String?
    @State private var isShowingScanner = false
    @State private var isShowingPhotoPicker = false
    @State private var isRecognizing = false
    @State private var isTranslating = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var sourceAccent: SpeechAccent = .american
    @StateObject private var speechService = SpeechService()

    private let ocrService = OCRService()

    var body: some View {
        NavigationStack {
            Form {
                Section("英文原文") {
                    TextEditor(text: $sourceText)
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("发音", selection: $sourceAccent) {
                        ForEach(SpeechAccent.allCases) { accent in
                            Text(accent.title).tag(accent)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Button {
                            speakSource(accent: sourceAccent)
                        } label: {
                            Label("\(sourceAccent.title)朗读", systemImage: "speaker.wave.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(cleanSourceText.isEmpty)

                        Button {
                            translateSource()
                        } label: {
                            Label("翻译中文", systemImage: "character.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(cleanSourceText.isEmpty || isTranslating)
                    }
                }

                Section("中文翻译") {
                    if isTranslating {
                        ProgressView("翻译中")
                    } else if let translationError {
                        Text(translationError)
                            .foregroundStyle(.secondary)
                    } else if translatedText.isEmpty {
                        Text("点击“翻译中文”后显示结果")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(translatedText)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("文章翻译")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            startScan()
                        } label: {
                            Label("扫描文章", systemImage: "doc.viewfinder")
                        }

                        Button {
                            isShowingPhotoPicker = true
                        } label: {
                            Label("导入文章图片", systemImage: "photo")
                        }

                        Button {
                            sourceText = ""
                            translatedText = ""
                            translationError = nil
                        } label: {
                            Label("清空", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入文章")
                }
            }
            .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .overlay {
                if isRecognizing {
                    ProgressView("识别中")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .fullScreenCover(isPresented: $isShowingScanner) {
                DocumentScannerView { images in
                    recognize(images)
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, item in
                loadPhoto(item)
            }
            .translationTask(translationConfiguration) { session in
                await runTranslation(session)
            }
            .onDisappear {
                speechService.stop()
            }
        }
    }

    private var cleanSourceText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startScan() {
        #if targetEnvironment(simulator)
        translationError = "模拟器没有真实摄像头。请用“导入文章图片”或直接粘贴英文；真机上可以扫描。"
        return
        #else
        guard VNDocumentCameraViewController.isSupported else {
            translationError = "当前设备不支持文档扫描。"
            return
        }
        isShowingScanner = true
        #endif
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        isRecognizing = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw OCRService.OCRServiceError.invalidImage
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                }
                recognize([image])
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
                    isRecognizing = false
                    translationError = error.localizedDescription
                }
            }
        }
    }

    private func recognize(_ images: [UIImage]) {
        isRecognizing = true
        Task {
            do {
                let text = try await ocrService.recognizeText(from: images)
                await MainActor.run {
                    isRecognizing = false
                    sourceText = text
                    translatedText = ""
                    translationError = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "没有识别到英文内容。" : nil
                }
            } catch {
                await MainActor.run {
                    isRecognizing = false
                    translationError = error.localizedDescription
                }
            }
        }
    }

    private func speakSource(accent: SpeechAccent) {
        speechService.speak(cleanSourceText, rate: 0.45, repetitions: 1, accent: accent)
    }

    private func translateSource() {
        translatedText = ""
        translationError = nil
        isTranslating = true
        translationConfiguration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
        translationConfiguration?.invalidate()
    }

    @MainActor
    private func runTranslation(_ session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(cleanSourceText)
            translatedText = response.targetText
            translationError = nil
        } catch {
            translationError = "系统翻译暂不可用：\(error.localizedDescription)。请确认设备系统支持翻译，并已安装英文到中文语言包。"
        }
        isTranslating = false
    }
}
