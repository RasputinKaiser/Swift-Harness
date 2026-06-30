import SwiftUI

struct MemoryPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var selectedRecord: MemoryRecord?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
                .navigationTitle("Memory Fabric")
                .navigationSubtitle("\(store.memory.records.count) of \(store.memory.totalCount)")
        } detail: {
            if let r = selectedRecord {
                MemoryDetail(record: r, onArchive: {
                    Task {
                        await store.memory.archive(r)
                        if selectedRecord?.id == r.id { selectedRecord = nil }
                    }
                })
            } else {
                ContentUnavailableView(
                    "Select a record",
                    systemImage: "brain.head.profile",
                    description: Text("Pick a memory record on the left to see its provenance, tags, and full body.")
                )
            }
        }
        .task { await store.memory.bootstrap() }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            list
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Memory Fabric…", text: Binding(
                    get: { store.memory.query },
                    set: { store.memory.query = $0 }
                ))
                .textFieldStyle(.plain)
                .onSubmit { Task { await store.memory.search() } }
                if store.memory.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                ForEach(["learning", "work", "knowledge"], id: \.self) { tier in
                    TierChip(tier: tier,
                             selected: store.memory.selectedTiers.contains(tier))
                        .onTapGesture {
                            if store.memory.selectedTiers.contains(tier) {
                                store.memory.selectedTiers.remove(tier)
                            } else {
                                store.memory.selectedTiers = [tier]  // single-select
                            }
                        }
                }
                Spacer()
                Menu {
                    ForEach(MemorySort.allCases, id: \.self) { mode in
                        Button {
                            store.memory.sort = mode
                        } label: {
                            HStack {
                                Text(mode.label)
                                if store.memory.sort == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(store.memory.sort.label, systemImage: "arrow.up.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
                Toggle(isOn: Binding(
                    get: { store.memory.showArchived },
                    set: { store.memory.showArchived = $0 }
                )) {
                    Label("Archived", systemImage: "archivebox")
                        .font(.caption2)
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var list: some View {
        if store.memory.records.isEmpty {
            if let err = store.memory.lastError {
                ContentUnavailableView(
                    "Search failed",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(err).foregroundStyle(.red)
                )
            } else {
                ContentUnavailableView(
                    store.memory.isLoading ? "Searching…" : "No records",
                    systemImage: "brain.head.profile"
                )
            }
        } else {
            List(store.memory.records, selection: $selectedRecord) { rec in
                MemoryRow(record: rec)
                    .tag(rec.id)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

private struct TierChip: View {
    let tier: String
    let selected: Bool
    var body: some View {
        Text(tier.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(selected ? Color(tierTint(tier)).opacity(0.25) : Color.gray.opacity(0.1),
                       in: Capsule())
            .foregroundStyle(selected ? Color(tierTint(tier)) : .secondary)
    }
    private func tierTint(_ t: String) -> String {
        switch t.lowercased() {
        case "learning": "blue"
        case "work": "purple"
        case "knowledge": "teal"
        default: "gray"
        }
    }
}

private struct MemoryRow: View {
    let record: MemoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.tier.uppercased())
                    .font(.caption2.bold().monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(record.tierTint).opacity(0.18), in: Capsule())
                    .foregroundStyle(Color(record.tierTint))
                if let conf = record.confidence {
                    Text(conf)
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: Capsule())
                        .foregroundStyle(confidenceTint(conf))
                }
                if let s = record.score {
                    Text("·\(s)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(record.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(record.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(record.dateLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private func confidenceTint(_ c: String) -> Color {
        switch c.lowercased() {
        case "high": .green
        case "medium": .orange
        case "low": .red
        default: .gray
        }
    }
}

private struct MemoryDetail: View {
    let record: MemoryRecord
    let onArchive: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    badges
                    bodyBlock
                    provenanceSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: onArchive) {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Write to ~/.ncode/memory_archive.jsonl and remove from list")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title)
                .font(.headline)
            HStack(spacing: 6) {
                Text(record.id)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(record.dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            Badge(text: record.tier.uppercased(), tint: Color(record.tierTint))
            if let conf = record.confidence {
                Badge(text: "conf=\(conf)", tint: .gray)
            }
            Badge(text: record.provenance.type, tint: .blue)
            ForEach(record.tags.prefix(5), id: \.self) { tag in
                Badge(text: tag, tint: .secondary)
            }
            if let s = record.score {
                Badge(text: "score=\(s)", tint: .gray)
            }
        }
    }

    private var bodyBlock: some View {
        Text(record.body)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var provenanceSection: some View {
        GroupBox("Provenance") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Type", value: record.provenance.type)
                LabeledContent("Detail", value: record.provenance.detail.isEmpty ? "(empty)" : record.provenance.detail)
                if let ev = record.provenance.evidencePath, !ev.isEmpty {
                    LabeledContent("Evidence") {
                        Text(ev)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down.circle")
                .foregroundStyle(.secondary)
            Text("Scope: \(record.scope)")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Status: \(record.status ?? "?")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}