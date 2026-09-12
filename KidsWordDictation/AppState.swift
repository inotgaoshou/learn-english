import Foundation
import SwiftUI

final class AppState: ObservableObject {
    @Published var wordLists: [WordList] = [] {
        didSet {
            saveWordLists()
        }
    }

    @Published var categories: [String] = [] {
        didSet {
            saveCategories()
        }
    }

    @Published var storageError: String?

    private var store: WordListStore?
    private let categoriesKey = "KidsWordDictation.categories"

    init() {
        do {
            let store = try WordListStore()
            self.store = store
            self.wordLists = try store.load()
            self.categories = loadCategories(merging: self.wordLists)
        } catch {
            self.store = nil
            self.storageError = error.localizedDescription
            self.categories = loadCategories(merging: [])
        }
    }

    var categoryNames: [String] {
        normalizedCategories(from: categories + wordLists.map(\.category))
    }

    func addWordList(title: String, category: String, words: [WordItem]) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = "Unit \(wordLists.count + 1)"
        let list = WordList(
            title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
            category: cleanCategory.isEmpty ? "未分类" : cleanCategory,
            words: deduplicated(words)
        )
        wordLists.insert(list, at: 0)
        addCategory(cleanCategory)
    }

    func addCategory(_ category: String) {
        let cleanCategory = normalizedCategory(category)
        guard !cleanCategory.isEmpty && cleanCategory != "未分类" else {
            return
        }
        guard !categories.contains(where: { $0.caseInsensitiveCompare(cleanCategory) == .orderedSame }) else {
            return
        }
        categories.append(cleanCategory)
        categories = normalizedCategories(from: categories)
    }

    func renameCategory(_ oldCategory: String, to newCategory: String) {
        let cleanOldCategory = normalizedCategory(oldCategory)
        let cleanNewCategory = normalizedCategory(newCategory)
        guard !cleanOldCategory.isEmpty,
              cleanOldCategory != "未分类",
              !cleanNewCategory.isEmpty,
              cleanNewCategory != "未分类",
              cleanOldCategory.caseInsensitiveCompare(cleanNewCategory) != .orderedSame else {
            return
        }

        for index in wordLists.indices where wordLists[index].category.caseInsensitiveCompare(cleanOldCategory) == .orderedSame {
            wordLists[index].category = cleanNewCategory
        }

        categories.removeAll { $0.caseInsensitiveCompare(cleanOldCategory) == .orderedSame }
        categories.append(cleanNewCategory)
        categories = normalizedCategories(from: categories)
    }

    func deleteCategory(_ category: String) {
        let cleanCategory = normalizedCategory(category)
        guard !cleanCategory.isEmpty && cleanCategory != "未分类" else {
            return
        }

        for index in wordLists.indices where wordLists[index].category.caseInsensitiveCompare(cleanCategory) == .orderedSame {
            wordLists[index].category = "未分类"
        }

        categories.removeAll { $0.caseInsensitiveCompare(cleanCategory) == .orderedSame }
        categories = normalizedCategories(from: categories)
    }

    func deleteWordLists(at offsets: IndexSet) {
        wordLists.remove(atOffsets: offsets)
    }

    func deleteWordList(id: WordList.ID) {
        wordLists.removeAll { $0.id == id }
    }

    private func saveWordLists() {
        guard let store else {
            return
        }

        do {
            try store.save(wordLists)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func loadCategories(merging wordLists: [WordList]) -> [String] {
        let savedCategories = UserDefaults.standard.stringArray(forKey: categoriesKey) ?? []
        return normalizedCategories(from: savedCategories + wordLists.map(\.category))
    }

    private func saveCategories() {
        UserDefaults.standard.set(normalizedCategories(from: categories), forKey: categoriesKey)
    }

    private func normalizedCategories(from values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { normalizedCategory($0) }
            .filter { !$0.isEmpty && $0 != "未分类" }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalizedCategory(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deduplicated(_ words: [WordItem]) -> [WordItem] {
        var seen = Set<String>()
        return words.filter { word in
            !word.normalizedText.isEmpty && seen.insert(word.normalizedText).inserted
        }
    }
}
