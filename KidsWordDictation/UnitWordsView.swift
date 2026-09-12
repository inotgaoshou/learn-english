import PhotosUI
import SwiftUI
import VisionKit

struct UnitWordsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isShowingScanner = false
    @State private var isShowingManualAdd = false
    @State private var isShowingCategoryAdd = false
    @State private var scanReview: ScanReviewData?
    @State private var alertMessage: String?
    @State private var categoryToDelete: String?
    @State private var categoryToRename: CategoryRenameData?
    @State private var isRecognizing = false
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let ocrService = OCRService()

    var body: some View {
        Group {
            if appState.wordLists.isEmpty && appState.categoryNames.isEmpty {
                ContentUnavailableView("暂无分类和单元", systemImage: "text.book.closed", description: Text("点击右上角先创建分类，或直接添加单元词语"))
            } else {
                List {
                    ForEach(categoryGroups, id: \.category) { group in
                        Section {
                            if group.items.isEmpty {
                                Text("暂无单元，点击右上角 + 添加到此分类")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(group.items) { item in
                                    if let binding = binding(for: item.id) {
                                        NavigationLink {
                                            WordListDetailView(wordList: binding)
                                        } label: {
                                            WordListRow(wordList: item)
                                        }
                                    }
                                }
                                .onDelete { offsets in
                                    deleteWordLists(at: offsets, in: group.items)
                                }
                            }
                        } header: {
                            CategorySectionHeader(
                                category: group.category,
                                canEdit: group.category != "未分类",
                                onRename: {
                                    categoryToRename = CategoryRenameData(name: group.category)
                                },
                                onDelete: {
                                    categoryToDelete = group.category
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("单元词语")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingCategoryAdd = true
                    } label: {
                        Label("创建分类", systemImage: "folder.badge.plus")
                    }

                    Divider()

                    Button {
                        startScan()
                    } label: {
                        Label("扫描单元词语", systemImage: "doc.viewfinder")
                    }

                    Button {
                        isShowingPhotoPicker = true
                    } label: {
                        Label("导入图片识别", systemImage: "photo")
                    }

                    Button {
                        isShowingManualAdd = true
                    } label: {
                        Label("手动录入单元", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加单元")
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
                recognize(images: images)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingManualAdd) {
            AddWordListView(categories: appState.categoryNames) { title, category, words in
                appState.addWordList(title: title, category: category, words: words)
            }
        }
        .sheet(isPresented: $isShowingCategoryAdd) {
            AddCategoryView { category in
                appState.addCategory(category)
            }
        }
        .sheet(item: $categoryToRename) { data in
            RenameCategoryView(category: data.name) { newName in
                appState.renameCategory(data.name, to: newName)
            }
        }
        .sheet(item: $scanReview) { review in
            ScanReviewView(review: review, categories: appState.categoryNames) { title, category, words in
                appState.addWordList(title: title, category: category, words: words)
                scanReview = nil
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            loadPhoto(item)
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil || appState.storageError != nil },
            set: { _ in
                alertMessage = nil
                appState.storageError = nil
            }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? appState.storageError ?? "")
        }
        .alert("删除分类？", isPresented: Binding(
            get: { categoryToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    categoryToDelete = nil
                }
            }
        )) {
            Button("删除分类", role: .destructive) {
                if let categoryToDelete {
                    appState.deleteCategory(categoryToDelete)
                }
                categoryToDelete = nil
            }
            Button("取消", role: .cancel) {
                categoryToDelete = nil
            }
        } message: {
            Text("只删除分类名称；分类下的单元会移动到“未分类”，不会删除单词。")
        }
    }

    private var categoryGroups: [(category: String, items: [WordList])] {
        let groups = Dictionary(grouping: appState.wordLists) { wordList in
            normalizedCategory(wordList.category)
        }
        let categories = Set(groups.keys).union(appState.categoryNames)

        return categories
            .map { category in
                let items = groups[category] ?? []
                return (
                    category: category,
                    items: items.sorted { lhs, rhs in
                        lhs.createdAt > rhs.createdAt
                    }
                )
            }
            .sorted { lhs, rhs in
                if lhs.category == "未分类" {
                    return false
                }
                if rhs.category == "未分类" {
                    return true
                }
                return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
            }
    }

    private func binding(for id: WordList.ID) -> Binding<WordList>? {
        guard let index = appState.wordLists.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $appState.wordLists[index]
    }

    private func normalizedCategory(_ category: String) -> String {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanCategory.isEmpty ? "未分类" : cleanCategory
    }

    private func deleteWordLists(at offsets: IndexSet, in items: [WordList]) {
        for offset in offsets {
            appState.deleteWordList(id: items[offset].id)
        }
    }

    private func startScan() {
        #if targetEnvironment(simulator)
        alertMessage = "模拟器没有真实摄像头。请用“导入图片识别”或“手动录入单元”；真机上可以直接扫描。"
        return
        #else
        guard VNDocumentCameraViewController.isSupported else {
            alertMessage = "当前设备不支持文档扫描，请在真机上使用摄像头，或先手动录入单元。"
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
                try await recognizeImage(image)
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
                    isRecognizing = false
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func recognize(images: [UIImage]) {
        isRecognizing = true
        Task {
            do {
                let words = try await ocrService.recognizeWords(from: images)
                showRecognizedWords(words)
            } catch {
                await MainActor.run {
                    isRecognizing = false
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func recognizeImage(_ image: UIImage) async throws {
        let words = try await ocrService.recognizeWords(from: [image])
        showRecognizedWords(words)
    }

    @MainActor
    private func showRecognizedWords(_ words: [WordItem]) {
        isRecognizing = false
        if words.isEmpty {
            alertMessage = "没有识别到英文单词。"
        } else {
            scanReview = ScanReviewData(words: words)
        }
    }
}

private struct CategoryRenameData: Identifiable {
    let id = UUID()
    let name: String
}

private struct CategorySectionHeader: View {
    let category: String
    let canEdit: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(category)
            Spacer()
            if canEdit {
                Menu {
                    Button {
                        onRename()
                    } label: {
                        Label("修改分类名", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除分类", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("管理 \(category)")
            }
        }
    }
}

private struct WordListRow: View {
    let wordList: WordList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(wordList.title)
                .font(.headline)
            HStack(spacing: 10) {
                if !wordList.category.isEmpty {
                    Label(wordList.category, systemImage: "folder")
                }
                Label("\(wordList.words.count)", systemImage: "textformat.abc")
                Text(wordList.createdAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category = ""

    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    TextField("例如 KET / 家庭 / 学校 / 食物", text: $category)
                }
            }
            .navigationTitle("创建分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(category)
                        dismiss()
                    }
                    .disabled(category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct RenameCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: String

    let originalCategory: String
    let onSave: (String) -> Void

    init(category: String, onSave: @escaping (String) -> Void) {
        self.originalCategory = category
        self._category = State(initialValue: category)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    TextField("分类名称", text: $category)
                }
            }
            .navigationTitle("修改分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(category)
                        dismiss()
                    }
                    .disabled(category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
