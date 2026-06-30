import SwiftUI

/// Skills marketplace mirror — browse all installed skills across
/// ~/.ncode/skills/ and ~/.codex/skills/. Shows name, description, source
/// location, and file size. Search filter by name or description.
struct SkillsPane: View {
    @State private var skills: [SkillInfo] = []
    @State private var searchText = ""
    @State private var selectedSkill: SkillInfo?
    @State private var skillBody: String?

    var body: some View {
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                .navigationTitle("Skills")
                .navigationSubtitle("\(skills.count) installed")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                }
        } detail: {
            if let skill = selectedSkill {
                SkillDetailView(skill: skill, rawBody: skillBody ?? "")
            } else {
                ContentUnavailableView("Select a skill", systemImage: "puzzlepiece.extension")
            }
        }
        .task { if skills.isEmpty { refresh() } }
    }

    private var list: some View {
        let filtered = skills.filter { s in
            searchText.isEmpty ||
            s.name.localizedCaseInsensitiveContains(searchText) ||
            s.description.localizedCaseInsensitiveContains(searchText)
        }
        return List(selection: $selectedSkill) {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Filter skills…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            Section("Installed (\(filtered.count))") {
                ForEach(filtered) { skill in
                    SkillRow(skill: skill).tag(skill)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func refresh() {
        skills = []
        let dirs = [
            (URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ncode/skills", isDirectory: true), "ncode"),
            (URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/skills", isDirectory: true), "codex"),
        ]
        for (dir, source) in dirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let skillFile = entry.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
                guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }
                let (fm, _) = parseFrontmatter(content)
                let name = fm["name"] ?? entry.lastPathComponent
                let desc = fm["description"] ?? "(no description)"
                let size = (try? skillFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                skills.append(SkillInfo(
                    id: "\(source)/\(name)",
                    name: name,
                    description: desc,
                    sourceDir: source,
                    path: skillFile.path,
                    bodyContent: content,
                    fileSize: size
                ))
            }
        }
        skills.sort(by: { $0.name < $1.name })
    }

    private func parseFrontmatter(_ text: String) -> ([String: String], String) {
        guard text.hasPrefix("---") else { return ([:], text) }
        let lines = text.split(separator: "\n", maxSplits: 200, omittingEmptySubsequences: false)
        var fm: [String: String] = [:]
        var body = ""
        var fmEnded = false
        for line in lines.dropFirst() {
            if line.hasPrefix("---") { fmEnded = true; continue }
            if !fmEnded {
                if let colon = line.firstIndex(of: ":") {
                    let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                    var val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    if val.hasPrefix("\"") && val.hasSuffix("\"") { val.removeFirst(); val.removeLast() }
                    fm[key] = val
                }
            } else {
                body += line + "\n"
            }
        }
        return (fm, body)
    }
}

struct SkillInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let sourceDir: String
    let path: String
    let bodyContent: String
    let fileSize: Int

    var sizeLabel: String {
        if fileSize > 1024 { return "\(fileSize / 1024)KB" }
        return "\(fileSize)B"
    }
}

private struct SkillRow: View {
    let skill: SkillInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension.fill")
                .foregroundStyle(skill.sourceDir == "ncode" ? .blue : .purple)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.callout.weight(.medium))
                    Text(skill.sourceDir)
                        .font(.caption2.bold())
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(skill.sourceDir == "ncode" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(skill.sourceDir == "ncode" ? .blue : .purple)
                }
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Text(skill.sizeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct SkillDetailView: View {
    let skill: SkillInfo
    let rawBody: String
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                descriptionCard
                contentBlock
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(skill.name)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2)
                .foregroundStyle(skill.sourceDir == "ncode" ? .blue : .purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.title3.bold())
                Text(skill.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(skill.sizeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var descriptionCard: some View {
        Text(skill.description)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var contentBlock: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(skill.bodyContent.prefix(3000))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        } label: {
            Label("SKILL.md content", systemImage: "doc.text.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}