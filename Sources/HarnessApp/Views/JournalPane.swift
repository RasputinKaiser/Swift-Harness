import SwiftUI

struct JournalPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var rawText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                if let text = rawText {
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    EmptyState(
                        "No journal yet",
                        systemImage: "book",
                        description: "Run /improve to populate ~/.ncode/improvements.md with self-correction sweeps.",
                        actionTitle: "Refresh now",
                        action: { Task { await reload() } },
                        secondaryInfo: "~/.ncode/improvements.md"
                    )
                    .padding(.top, 60)
                }
            }
            if let entry = store.latestImprovement {
                Divider()
                latestCard(entry)
            }
        }
        .navigationTitle("Journal")
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("~/.ncode/improvements.md")
                    .font(.headline)
                if let mtime = store.latestImprovementAt {
                    Text("Last modified \(mtime.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func latestCard(_ entry: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Latest entry")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(6)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func reload() async {
        rawText = try? String(contentsOf: HarnessClient.improvementsPath, encoding: .utf8)
    }
}