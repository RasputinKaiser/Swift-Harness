import SwiftUI

struct ManifestPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var category: Category = .hooks
    @State private var searchText: String = ""

    enum Category: String, CaseIterable, Hashable {
        case hooks, agents, commands
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .hooks: "fork.arrow.up.right.down"
            case .agents: "person.crop.badge.checkmark"
            case .commands: "command"
            }
        }
        var count: Int { 0 }  // populated from store
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            searchField
            Divider()
            listView
            Divider()
            footer
        }
        .navigationTitle("Manifest")
        .task {
            if store.manifest.hooks.isEmpty {
                store.manifest.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let meta = store.manifest.pluginMeta {
                HStack(spacing: 8) {
                    Text(meta.name)
                        .font(.title2.bold())
                    Text("v\(meta.version)")
                        .font(.caption2.bold().monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: Capsule())
                }
                Text(meta.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    pill("hooks", String(meta.hooksCount), .orange)
                    pill("agents", String(meta.agentsCount), .purple)
                    pill("commands", String(meta.commandsCount), .blue)
                    Spacer()
                    Text(meta.authorName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            } else {
                Text("No plugin manifest loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(tint)
            Text(value)
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Category.allCases, id: \.self) { c in
                Button {
                    category = c
                } label: {
                    Label(c.label, systemImage: c.icon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(category == c ? Color.accentColor : .secondary)
                .background(category == c ? Color.accentColor.opacity(0.1) : Color.clear,
                           in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Filter…", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var listView: some View {
        switch category {
        case .hooks: hooksList
        case .agents: agentsList
        case .commands: commandsList
        }
    }

    @ViewBuilder
    private var hooksList: some View {
        let filtered = store.manifest.hooks.filter { entry in
            searchText.isEmpty ||
                entry.event.localizedCaseInsensitiveContains(searchText) ||
                entry.script.localizedCaseInsensitiveContains(searchText)
        }
        if filtered.isEmpty {
            ContentUnavailableView("No hooks match", systemImage: "fork.arrow.up.right.down")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered) { hook in
                        HookManifestRow(hook: hook)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var agentsList: some View {
        let filtered = store.manifest.agents.filter { agent in
            searchText.isEmpty ||
                agent.name.localizedCaseInsensitiveContains(searchText) ||
                agent.description.localizedCaseInsensitiveContains(searchText)
        }
        if filtered.isEmpty {
            ContentUnavailableView("No agents match", systemImage: "person.crop.badge.checkmark")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered) { agent in
                        AgentManifestRow(agent: agent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var commandsList: some View {
        let filtered = store.manifest.commands.filter { cmd in
            searchText.isEmpty ||
                cmd.name.localizedCaseInsensitiveContains(searchText) ||
                cmd.description.localizedCaseInsensitiveContains(searchText)
        }
        if filtered.isEmpty {
            ContentUnavailableView("No commands match", systemImage: "command")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered) { cmd in
                        CommandManifestRow(command: cmd)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Read-only view — edit surfaces in the source repo at ~/Code/harness-self-improvement/")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let last = store.manifest.lastRefresh {
                Text(last.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

private struct HookManifestRow: View {
    let hook: ManifestStore.HookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(hook.event)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.orange)
                Text(matcher)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(hook.timeout)s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(hook.script)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            if let status = hook.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var matcher: String {
        hook.matcher.isEmpty ? "(all)" : hook.matcher
    }
}

private struct AgentManifestRow: View {
    let agent: ManifestStore.AgentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.badge.checkmark")
                    .foregroundStyle(.purple)
                Text(agent.name)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(agent.model)
                    .font(.caption2.bold().monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule())
            }
            if !agent.description.isEmpty {
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(agent.filePath)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CommandManifestRow: View {
    let command: ManifestStore.CommandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .foregroundStyle(.blue)
                Text("/\(command.name)")
                    .font(.system(.callout, design: .monospaced).bold())
            }
            if !command.description.isEmpty {
                Text(command.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(command.filePath)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}