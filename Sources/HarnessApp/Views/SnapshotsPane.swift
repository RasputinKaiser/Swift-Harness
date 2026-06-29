import SwiftUI

struct SnapshotsPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var selectedHash: String?
    @State private var showRestoreSheet = false
    @State private var showNewSnapshotSheet = false
    @State private var newSnapshotReason = ""

    var body: some View {
        NavigationSplitView {
            snapshotList
                .navigationTitle("Snapshots")
                .navigationSubtitle("\(store.snapshotStore.snapshots.count) total")
                .toolbar { toolbarLeft }
        } detail: {
            if let snap = selectedSnapshot {
                SnapshotDetail(snapshot: snap,
                                diff: store.snapshotStore.diffsByHash[snap.hash] ?? [])
            } else {
                ContentUnavailableView(
                    "Select a snapshot",
                    systemImage: "archivebox",
                    description: Text("Pick a snapshot on the left to see its manifest and diff vs the live tree.")
                )
            }
        }
        .task {
            if store.snapshotStore.snapshots.isEmpty {
                store.snapshotStore.refresh()
            }
        }
        .sheet(isPresented: $showRestoreSheet) {
            if let snap = selectedSnapshot {
                RestoreConfirmationSheet(snapshot: snap) {
                    Task {
                        await store.snapshotStore.restore(hash: snap.hash)
                        showRestoreSheet = false
                    }
                }
            }
        }
        .sheet(isPresented: $showNewSnapshotSheet) {
            NewSnapshotSheet(reason: $newSnapshotReason) { reason in
                Task {
                    await store.snapshotStore.takeSnapshot(reason: reason)
                    showNewSnapshotSheet = false
                    newSnapshotReason = ""
                }
            }
        }
    }

    // MARK: - List

    private var snapshotList: some View {
        List(store.snapshotStore.snapshots, selection: $selectedHash) { snap in
            SnapshotRow(snapshot: snap, drifted: store.snapshotStore.driftedCount(snap))
                .tag(snap.hash)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ToolbarContentBuilder
    private var toolbarLeft: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.snapshotStore.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        ToolbarItem {
            Button {
                showNewSnapshotSheet = true
            } label: {
                Label("Take snapshot", systemImage: "camera.badge.ellipsis")
            }
        }
    }

    private var selectedSnapshot: Snapshot? {
        store.snapshotStore.snapshots.first(where: { $0.hash == selectedHash })
    }
}

private struct SnapshotRow: View {
    let snapshot: Snapshot
    let drifted: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.hash.prefix(12))
                    .font(.system(.body, design: .monospaced))
                if drifted > 0 {
                    Label("\(drifted) drifted", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                } else {
                    Label("clean", systemImage: "checkmark.seal.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            Text(snapshot.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 8) {
                Text("\(snapshot.files.count) files")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if let d = snapshot.createdAtDate {
                    Text(d.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SnapshotDetail: View {
    let snapshot: Snapshot
    let diff: [SnapshotFileDiff]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff) { d in
                        DiffRow(diff: d)
                        Divider().opacity(0.4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRestoreSheet = true
                } label: {
                    Label("Restore…", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.hash)
                    .font(.system(.headline, design: .monospaced))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(snapshot.reason)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text("\(snapshot.files.count) files")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if let d = snapshot.createdAtDate {
                    Text(d.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        let driftCount = diff.filter { $0.drifted }.count
        let missing = diff.filter { $0.liveMissing }.count
        return HStack(spacing: 12) {
            Label("\(diff.count)", systemImage: "doc")
                .help("Files in snapshot")
            Label("\(driftCount)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(driftCount > 0 ? .red : .secondary)
                .help("Changed since snapshot")
            Label("\(missing)", systemImage: "minus.circle")
                .foregroundStyle(missing > 0 ? .orange : .secondary)
                .help("No longer in live tree")
            Spacer()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var showRestoreSheet = false
}

private struct DiffRow: View {
    let diff: SnapshotFileDiff

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(diff.name)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Text(diff.snapshotHash.prefix(8))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            if let live = diff.liveHash {
                Text(live.prefix(8))
                    .font(.caption2.monospaced())
                    .foregroundStyle(diff.drifted ? .red : .secondary)
            } else {
                Text("missing")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if diff.liveMissing {
            Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
        } else if diff.drifted {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

private struct RestoreConfirmationSheet: View {
    let snapshot: Snapshot
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Restore snapshot?")
                .font(.title3.bold())
            Text("This will overwrite the current ~/.ncode/scripts/ contents with the snapshot files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snapshot: \(snapshot.hash.prefix(16))")
                        .font(.system(.callout, design: .monospaced))
                    Text("Reason: \(snapshot.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.files.count) files will be restored")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text("A pre-restore backup is automatically created by restore_harness.py — if restore goes wrong, the previous state can be recovered from the snapshot list.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack {
                Button("Cancel", role: .cancel) {}
                Button("Restore", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct NewSnapshotSheet: View {
    @Binding var reason: String
    let onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Take a new snapshot")
                .font(.title3.bold())
            Text("Runs `python3 ~/.ncode/scripts/snapshot_harness.py --reason <reason>`")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Reason (e.g. before refactor session)", text: $reason)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            HStack {
                Button("Cancel", role: .cancel) {}
                Button("Snapshot", action: { submit() })
                    .buttonStyle(.borderedProminent)
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func submit() {
        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty else { return }
        onSubmit(r)
    }
}