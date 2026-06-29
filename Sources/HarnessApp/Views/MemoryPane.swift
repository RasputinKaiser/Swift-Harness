import SwiftUI

struct MemoryPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var selectedRecord: MemoryFabricClient.Record?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .navigationTitle("Memory Fabric")
        .task {
            if store.recentRecords.isEmpty {
                await store.refreshStatus()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent records (scoped to ~/.ncode)")
                    .font(.headline)
                Text("\(store.recentRecords.count) shown · \(store.memoryRecordCount) total in store")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refreshStatus() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if store.recentRecords.isEmpty {
            ContentUnavailableView(
                "No records yet",
                systemImage: "brain.head.profile",
                description: Text("Memory Fabric will populate as tasks complete and sessions close.")
            )
        } else {
            List(store.recentRecords, selection: $selectedRecord) { record in
                MemoryRecordRow(record: record)
                    .tag(record)
            }
            .listStyle(.inset)
            if let r = selectedRecord {
                Divider()
                recordDetail(r)
            }
        }
    }

    private func recordDetail(_ r: MemoryFabricClient.Record) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.title)
                    .font(.headline)
                HStack(spacing: 6) {
                    Badge(text: r.tier.uppercased(), tint: tierTint(r.tier))
                    ForEach(r.tags.prefix(4), id: \.self) { tag in
                        Badge(text: tag, tint: .secondary)
                    }
                    if let conf = r.confidence {
                        Badge(text: "conf=\(conf)", tint: .gray)
                    }
                    if let ts = r.createdAt {
                        Badge(text: ts, tint: .gray)
                    }
                }
                Text(r.body)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
    }

    private func tierTint(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "learning": .blue
        case "work": .purple
        case "knowledge": .teal
        default: .gray
        }
    }
}

private struct MemoryRecordRow: View {
    let record: MemoryFabricClient.Record

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.tier.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.tertiary, in: Capsule())
                Text(record.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(record.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}