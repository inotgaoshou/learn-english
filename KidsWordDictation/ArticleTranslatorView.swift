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
    @State private var imageRegionSelection: ImportedImageSelection?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var sourceAccent: SpeechAccent = .american
    @State private var captureMode: ArticleCaptureMode = .fullPage
    @State private var isEditingSourceText = false
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
                    if isEditingSourceText {
                        TextEditor(text: $sourceText)
                            .frame(minHeight: 180)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: sourceText) { _, newValue in
                                refreshSegments(for: newValue)
                            }
                    } else {
                        articleReadingView
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

                    Button {
                        isEditingSourceText.toggle()
                    } label: {
                        Label(isEditingSourceText ? "阅读样式" : "编辑原文", systemImage: isEditingSourceText ? "text.book.closed" : "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(cleanSourceText.isEmpty)
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
            .sheet(item: $imageRegionSelection) { item in
                ImageRegionSelectionView(image: item.image) { selectedImage in
                    imageRegionSelection = nil
                    recognize([selectedImage])
                } onCancel: {
                    imageRegionSelection = nil
                }
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

    private var articleReadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if articleSegments.isEmpty {
                if cleanSourceText.isEmpty {
                    Text("导入或扫描后在这里显示英文内容")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                } else {
                    readableTextCard(title: "整页内容", text: cleanSourceText, isSelected: true)
                }
            } else {
                ForEach(articleSegments.indices, id: \.self) { index in
                    readableTextCard(
                        title: "内容块 \(index + 1)：\(articleSegments[index].title)",
                        text: articleSegments[index].text,
                        isSelected: selectedSegmentIndices.isEmpty || selectedSegmentIndices.contains(index)
                    )
                }
            }
        }
    }

    private func readableTextCard(title: String, text: String, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSelected {
                    Text("朗读范围")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            Text(text)
                .font(.title3)
                .lineSpacing(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.28) : Color.clear, lineWidth: 1)
        )
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

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw OCRService.OCRServiceError.invalidImage
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                    imageRegionSelection = ImportedImageSelection(image: image.normalizedForCropping())
                }
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
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

private struct ImportedImageSelection: Identifiable {
    let id = UUID()
    var image: UIImage
}

private struct ImageRegionSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onComplete: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var cropRect = CGRect(x: 0.06, y: 0.08, width: 0.88, height: 0.54)
    @State private var dragStartRect: CGRect?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("拖动蓝框选择要识别的教材区域")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                GeometryReader { proxy in
                    let imageFrame = fittedImageFrame(in: proxy.size)
                    ZStack {
                        Color.black.opacity(0.06)

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)

                        cropOverlay(in: imageFrame)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                VStack(spacing: 10) {
                    Button {
                        onComplete(image)
                        dismiss()
                    } label: {
                        Label("识别整张图片", systemImage: "doc.text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onComplete(image.cropped(toNormalized: cropRect))
                        dismiss()
                    } label: {
                        Label("识别框选区域", systemImage: "viewfinder.rectangular")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 14)
            }
            .navigationTitle("选择识别区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func cropOverlay(in imageFrame: CGRect) -> some View {
        let rect = cropRect.denormalized(in: imageFrame)

        return ZStack {
            Rectangle()
                .fill(.black.opacity(0.22))
                .mask {
                    Rectangle()
                        .overlay(
                            Rectangle()
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        )
                }
                .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.blue, lineWidth: 3)
                .background(Color.blue.opacity(0.08))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture(in: imageFrame))

            cropHandle(at: CGPoint(x: rect.minX, y: rect.minY), corner: .topLeft, imageFrame: imageFrame)
            cropHandle(at: CGPoint(x: rect.maxX, y: rect.minY), corner: .topRight, imageFrame: imageFrame)
            cropHandle(at: CGPoint(x: rect.minX, y: rect.maxY), corner: .bottomLeft, imageFrame: imageFrame)
            cropHandle(at: CGPoint(x: rect.maxX, y: rect.maxY), corner: .bottomRight, imageFrame: imageFrame)
        }
    }

    private func cropHandle(at point: CGPoint, corner: CropCorner, imageFrame: CGRect) -> some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .position(point)
            .gesture(resizeGesture(corner: corner, in: imageFrame))
    }

    private func moveGesture(in imageFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let dragStartRect else {
                    return
                }
                let dx = value.translation.width / max(imageFrame.width, 1)
                let dy = value.translation.height / max(imageFrame.height, 1)
                cropRect = dragStartRect.offsetBy(dx: dx, dy: dy).clampedToUnit()
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func resizeGesture(corner: CropCorner, in imageFrame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let dragStartRect else {
                    return
                }
                let dx = value.translation.width / max(imageFrame.width, 1)
                let dy = value.translation.height / max(imageFrame.height, 1)
                cropRect = dragStartRect.resized(corner: corner, dx: dx, dy: dy).clampedToUnit(minSize: 0.12)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func fittedImageFrame(in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

private enum CropCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private extension CGRect {
    func denormalized(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + minX * frame.width,
            y: frame.minY + minY * frame.height,
            width: width * frame.width,
            height: height * frame.height
        )
    }

    func clampedToUnit(minSize: CGFloat = 0.08) -> CGRect {
        let cleanWidth = min(max(width, minSize), 1)
        let cleanHeight = min(max(height, minSize), 1)
        let cleanX = min(max(minX, 0), 1 - cleanWidth)
        let cleanY = min(max(minY, 0), 1 - cleanHeight)
        return CGRect(x: cleanX, y: cleanY, width: cleanWidth, height: cleanHeight)
    }

    func resized(corner: CropCorner, dx: CGFloat, dy: CGFloat) -> CGRect {
        switch corner {
        case .topLeft:
            return CGRect(x: minX + dx, y: minY + dy, width: width - dx, height: height - dy)
        case .topRight:
            return CGRect(x: minX, y: minY + dy, width: width + dx, height: height - dy)
        case .bottomLeft:
            return CGRect(x: minX + dx, y: minY, width: width - dx, height: height + dy)
        case .bottomRight:
            return CGRect(x: minX, y: minY, width: width + dx, height: height + dy)
        }
    }
}

private extension UIImage {
    func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func cropped(toNormalized normalizedRect: CGRect) -> UIImage {
        let normalizedImage = normalizedForCropping()
        guard let cgImage = normalizedImage.cgImage else {
            return normalizedImage
        }

        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(cgImage.width),
            y: normalizedRect.minY * CGFloat(cgImage.height),
            width: normalizedRect.width * CGFloat(cgImage.width),
            height: normalizedRect.height * CGFloat(cgImage.height)
        ).integral

        guard let croppedImage = cgImage.cropping(to: pixelRect) else {
            return normalizedImage
        }

        return UIImage(cgImage: croppedImage, scale: normalizedImage.scale, orientation: .up)
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
