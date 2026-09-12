import PhotosUI
import SwiftUI
import Translation
import VisionKit

struct ArticleTranslatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var translationError: String?
    @State private var articleSegments: [ArticleTextSegment] = []
    @State private var selectedSegmentIndices: Set<Int> = []
    @State private var pendingTranslationText = ""
    @State private var isShowingScanner = false
    @State private var isShowingPhotoPicker = false
    @State private var isRecognizing = false
    @State private var isTranslating = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var sourceAccent: SpeechAccent = .american
    @State private var captureMode: ArticleCaptureMode = .fullPage
    @StateObject private var speechService = SpeechService()

    private let ocrService = OCRService()

    var body: some View {
        NavigationStack {
            Form {
                Section("拍摄模式") {
                    Picker("模式", selection: $captureMode) {
                        ForEach(ArticleCaptureMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: captureMode.systemImage)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(captureMode.headline)
                                .font(.headline)
                            Text(captureMode.guidance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        startScan()
                    } label: {
                        Label(captureMode.scanButtonTitle, systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isShowingPhotoPicker = true
                    } label: {
                        Label("从相册导入图片", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Section("英文原文") {
                    TextEditor(text: $sourceText)
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: sourceText) { _, newValue in
                            refreshSegments(for: newValue)
                        }

                    if !articleSegments.isEmpty {
                        contentBlockSelectionView
                    } else if !cleanSourceText.isEmpty {
                        Text("当前为整页内容。拍指定内容块时，请在扫描编辑页用 Adjust 框住目标区域。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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
                        .disabled(cleanSelectedSourceText.isEmpty)

                        Button {
                            translateSource()
                        } label: {
                            Label("翻译中文", systemImage: "character.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(cleanSelectedSourceText.isEmpty || isTranslating)
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
                            captureMode = .fullPage
                            startScan()
                        } label: {
                            Label("扫描文章", systemImage: "doc.viewfinder")
                        }

                        Button {
                            captureMode = .fullPage
                            isShowingPhotoPicker = true
                        } label: {
                            Label("导入文章图片", systemImage: "photo")
                        }

                        Button {
                            clearArticle()
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

    private var cleanSelectedSourceText: String {
        WordTextNormalizer.displayText(for: selectedSourceText)
    }

    private var selectedSourcePreview: String {
        selectedSegmentIndices.isEmpty ? cleanSourceText : cleanSelectedSourceText
    }

    private var selectedSourceText: String {
        guard !selectedSegmentIndices.isEmpty else {
            return sourceText
        }
        return selectedSegmentIndices
            .sorted()
            .filter { articleSegments.indices.contains($0) }
            .map { articleSegments[$0].text }
            .joined(separator: "\n\n")
    }

    private var selectionSummary: String {
        selectedSegmentIndices.isEmpty ? "当前使用整页内容" : "已选择 \(selectedSegmentIndices.count) 个内容块"
    }

    private var contentBlockSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("朗读/翻译范围")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    selectedSegmentIndices = []
                    clearTranslationResult()
                } label: {
                    Label("整页", systemImage: selectedSegmentIndices.isEmpty ? "checkmark.circle.fill" : "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    selectedSegmentIndices = Set(articleSegments.indices)
                    clearTranslationResult()
                } label: {
                    Label("全选", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            ForEach(articleSegments.indices, id: \.self) { index in
                contentBlockRow(index)
            }

            Text(selectedSourcePreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private func contentBlockRow(_ index: Int) -> some View {
        let isSelected = selectedSegmentIndices.contains(index)
        return Button {
            toggleSegmentSelection(index)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("内容块 \(index + 1)：\(articleSegments[index].title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(articleSegments[index].text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
                    updateSourceText(text, captureMode: captureMode)
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
        speechService.speak(cleanSelectedSourceText, rate: 0.45, repetitions: 1, accent: accent)
    }

    private func translateSource() {
        translatedText = ""
        translationError = nil
        pendingTranslationText = cleanSelectedSourceText
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
            let response = try await session.translate(pendingTranslationText)
            translatedText = response.targetText
            translationError = nil
        } catch {
            translationError = "系统翻译暂不可用：\(error.localizedDescription)。请确认设备系统支持翻译，并已安装英文到中文语言包。"
        }
        isTranslating = false
    }

    private func updateSourceText(_ text: String, captureMode: ArticleCaptureMode) {
        sourceText = text
        articleSegments = ArticleTextSegment.segments(from: text)
        if captureMode == .contentBlock, !articleSegments.isEmpty {
            selectedSegmentIndices = [0]
        } else {
            selectedSegmentIndices = []
        }
    }

    private func refreshSegments(for text: String) {
        articleSegments = ArticleTextSegment.segments(from: text)
        selectedSegmentIndices = selectedSegmentIndices.filter { articleSegments.indices.contains($0) }
    }

    private func clearArticle() {
        sourceText = ""
        translatedText = ""
        translationError = nil
        articleSegments = []
        selectedSegmentIndices = []
        pendingTranslationText = ""
        speechService.stop()
    }

    private func toggleSegmentSelection(_ index: Int) {
        if selectedSegmentIndices.contains(index) {
            selectedSegmentIndices.remove(index)
        } else {
            selectedSegmentIndices.insert(index)
        }
        clearTranslationResult()
    }

    private func clearTranslationResult() {
        translatedText = ""
        translationError = nil
    }
}

private struct ArticleTextSegment: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let text: String

    static func segments(from text: String) -> [ArticleTextSegment] {
        let blankLineSegments = text
            .components(separatedBy: "\n\n")
            .map(cleanBlock)
            .filter { !$0.isEmpty }

        if blankLineSegments.count > 1 {
            return blankLineSegments.map(segment)
        }

        let headingSegments = segmentsByHeadings(from: text)
        if headingSegments.count > 1 {
            return headingSegments
        }

        return []
    }

    private static func segmentsByHeadings(from text: String) -> [ArticleTextSegment] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { WordTextNormalizer.displayText(for: $0) }
            .filter { !$0.isEmpty }

        var segments: [ArticleTextSegment] = []
        var currentHeading = ""
        var currentLines: [String] = []

        for line in lines {
            if isContentBlockHeading(line) {
                if !currentLines.isEmpty {
                    segments.append(segment(heading: currentHeading, bodyLines: currentLines))
                    currentLines = []
                }
                currentHeading = line
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            segments.append(segment(heading: currentHeading, bodyLines: currentLines))
        }

        return segments.filter { $0.text.split(separator: " ").count >= 6 }
    }

    private static func segment(_ text: String) -> ArticleTextSegment {
        ArticleTextSegment(title: title(for: text), text: text)
    }

    private static func segment(heading: String, bodyLines: [String]) -> ArticleTextSegment {
        let body = bodyLines.joined(separator: "\n")
        let text = heading.isEmpty ? body : "\(heading)\n\(body)"
        return ArticleTextSegment(title: heading.isEmpty ? title(for: body) : heading, text: text)
    }

    private static func title(for text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { WordTextNormalizer.displayText(for: $0) }
            .first { !$0.isEmpty } ?? "内容"
        return String(firstLine.prefix(24))
    }

    private static func cleanBlock(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { WordTextNormalizer.displayText(for: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func isContentBlockHeading(_ line: String) -> Bool {
        if isExerciseHeading(line) {
            return true
        }

        if isShortUppercaseHeading(line) {
            return true
        }

        let lowercased = line.lowercased()
        return ["reading", "writing", "speaking", "grammar", "rules", "exam advice"].contains { lowercased.contains($0) }
    }

    private static func isShortUppercaseHeading(_ line: String) -> Bool {
        let letters = line.filter { $0.isLetter }
        guard letters.count >= 2, line.count <= 32 else {
            return false
        }
        guard line.rangeOfCharacter(from: CharacterSet.decimalDigits) == nil else {
            return false
        }
        return String(letters).uppercased() == String(letters)
    }

    private static func isExerciseHeading(_ line: String) -> Bool {
        guard line.count <= 96 else {
            return false
        }

        let lowercased = line.lowercased()
        if lowercased.hasPrefix("look ")
            || lowercased.hasPrefix("read ")
            || lowercased.hasPrefix("listen ")
            || lowercased.hasPrefix("complete ")
            || lowercased.hasPrefix("match ")
            || lowercased.hasPrefix("write ")
            || lowercased.hasPrefix("work ") {
            return true
        }

        return line.range(of: #"^\d+\s+[A-Z]"#, options: .regularExpression) != nil
    }
}

private enum ArticleCaptureMode: String, CaseIterable, Identifiable {
    case fullPage
    case contentBlock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullPage:
            return "整页"
        case .contentBlock:
            return "选块"
        }
    }

    var headline: String {
        switch self {
        case .fullPage:
            return "拍整页教材"
        case .contentBlock:
            return "拍指定内容块"
        }
    }

    var scanButtonTitle: String {
        switch self {
        case .fullPage:
            return "开始拍整页"
        case .contentBlock:
            return "开始框选内容"
        }
    }

    var systemImage: String {
        switch self {
        case .fullPage:
            return "doc.viewfinder"
        case .contentBlock:
            return "viewfinder.rectangular"
        }
    }

    var guidance: String {
        switch self {
        case .fullPage:
            return "适合整页教材。识别后可以选择整页，也可以勾选一个或多个内容块朗读、翻译。"
        case .contentBlock:
            return "适合只练某个题目、阅读框、邮件框或几段内容。拍完进入编辑页后，用 Adjust 尽量框住目标区域。"
        }
    }
}
