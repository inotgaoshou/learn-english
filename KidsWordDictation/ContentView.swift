import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("学习模块") {
                    NavigationLink {
                        UnitWordsView()
                    } label: {
                        ModuleRow(
                            title: "单元词语",
                            subtitle: "\(appState.wordLists.count) 个单元，支持扫描、手动录入、翻译、发音和听写",
                            systemImage: "text.book.closed"
                        )
                    }

                    NavigationLink {
                        ArticleTranslatorView()
                    } label: {
                        ModuleRow(
                            title: "文章翻译/朗读",
                            subtitle: "扫描或输入英文文章，翻译中文并播放美式/英式发音",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                }
            }
            .navigationTitle("英语学习")
        }
    }
}

private struct ModuleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}
