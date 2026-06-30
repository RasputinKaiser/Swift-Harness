import SwiftUI

struct PluginPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var reinstallTarget: PluginInstallManifest?
    @State private var rawCheckOutput: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            driftBanner
            actions
            Divider()
            fileList
            Divider()
            footer
        }
        .navigationTitle("Plugin")
        .task {
            if store.pluginMirror.drift == nil {
                store.pluginMirror.refresh()
            }
        }
        .sheet(item: $reinstallTarget) { m in
            ReinstallSheet(manifest: m, drift: store.pluginMirror.drift) {
                Task {
                    await store.pluginMirror.reinstall()
                    reinstallTarget = nil
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Self-Improvement-Plugin")
                    .font(.title2.bold())
                if let m = store.pluginMirror.manifest {
                    Text("v\(m.shortCommit)")
                        .font(.caption2.bold().monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            if let m = store.pluginMirror.manifest, let d = m.installedAtDate {
                Text("Installed \(d.formatted(date: .abbreviated, time: .shortened)) from branch `\(m.branch)`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not installed yet — run `install.sh` from the Self-Improvement-Plugin checkout.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var driftBanner: some View {
        if let dr = store.pluginMirror.drift {
            if dr.changedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Drift detected: \(dr.changedCount) file\(dr.changedCount == 1 ? "" : "s") differ")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                        Text("Reinstall to sync ~/.ncode/plugins/marketplaces/harness-local/")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.12))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("In sync with \(store.pluginMirror.sourceCommitShort)")
                        .font(.callout.bold())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green.opacity(0.08))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                reinstallTarget = store.pluginMirror.manifest
            } label: {
                Label("Reinstall", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.pluginMirror.isInstalling || store.pluginMirror.manifest == nil)
            .help("Runs install.sh to sync source repo to install cache")

            Button(action: checkDrift) {
                Label("Check drift", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .disabled(store.pluginMirror.isInstalling)

            if store.pluginMirror.isInstalling {
                ProgressView("Installing…")
                    .controlSize(.small)
                    .padding(.leading, 6)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func checkDrift() {
        Task { rawCheckOutput = await store.pluginMirror.checkDrift() }
    }

    @ViewBuilder
    private var fileList: some View {
        if let dr = store.pluginMirror.drift {
            // Show only changed files first, then unchanged
            let entries = dr.workingFiles.sorted { lhs, rhs in
                let l1 = lhs.value.status == .inSync ? 1 : 0
                let r1 = rhs.value.status == .inSync ? 1 : 0
                if l1 != r1 { return l1 < r1 }
                return lhs.key < rhs.key
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.key) { pair in
                        DriftRow(path: pair.key, triple: pair.value)
                        Divider().opacity(0.3)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        } else if let raw = rawCheckOutput {
            ScrollView {
                Text(raw)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } else {
            ContentUnavailableView(
                "No manifest yet",
                systemImage: "tray",
                description: Text("Run install.sh once from \(store.pluginMirror.sourceRepoPath) to populate ~/.ncode/.harness.installed.json")
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "gear")
                .foregroundStyle(.secondary)
            Text(store.pluginMirror.statusLabel)
                .font(.caption)
            if let last = store.pluginMirror.lastRefresh {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(last.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let err = store.pluginMirror.lastInstallError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

private struct DriftRow: View {
    let path: String
    let triple: DriftTriple

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: triple.status.icon)
                .foregroundStyle(Color(triple.status.tint))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(path)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Text(triple.status.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            hashLabel("installed", triple.installed, tint: .secondary)
            if let s = triple.source {
                hashLabel("source", s, tint: triple.source != triple.installed ? .orange : .secondary)
            }
            if let l = triple.live {
                hashLabel("live", l, tint: (l != triple.installed && l != triple.source) ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private func hashLabel(_ kind: String, _ hash: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(kind)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(String(hash.prefix(8)))
                .font(.caption2.monospaced())
                .foregroundStyle(tint)
        }
    }
}

private struct ReinstallSheet: View {
    let manifest: PluginInstallManifest
    let drift: PluginDriftSnapshot?
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Reinstall harness plugin?")
                .font(.title3.bold())
            Text("Runs install.sh — syncs the source repo into ~/.ncode/plugins/marketplaces/harness-local/.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Installed commit", value: String(manifest.commit.prefix(8)))
                    LabeledContent("Branch", value: manifest.branch)
                    if let d = drift {
                        LabeledContent("Files", value: "\(d.workingFiles.count)")
                        LabeledContent("Drifted", value: "\(d.changedCount)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text("install.sh runs snapshot_harness.py first (your previous scripts land in the Snapshots pane and can be restored).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack {
                Button("Cancel", role: .cancel) {}
                Button("Reinstall", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
