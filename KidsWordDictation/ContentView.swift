import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingPrivacyPolicy = false
    @AppStorage(OnlineCompletionSettings.storageKey) private var onlineCompletionEnabled = true

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

                Section("资料补全") {
                    Toggle(isOn: $onlineCompletionEnabled) {
                        Label("自动联网补全", systemImage: "network")
                    }
                    Text("内置资料没有音标时，仅发送单个英文词条（单词或短语）到免费在线词典；不会上传图片、文章或单词本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showingPrivacyPolicy = true
                    } label: {
                        Label("隐私说明", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("小鹿学习")
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
        }
    }
}

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private var policyText: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "隐私说明暂时无法读取，请重新打开应用。"
        }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(policyText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("隐私说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
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
