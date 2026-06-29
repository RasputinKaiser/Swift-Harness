import SwiftUI

struct TemplatesPane: View {
    @Environment(HarnessStore.self) private var store
    @State private var searchText = ""
    @State private var editingTemplate: PromptTemplate?
    @State private var showEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(store.templates.categories, id: \.self) { category in
                    categorySection(category)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTemplate = nil
                    showEditor = true
                } label: { Label("New", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) {
            TemplateEditor(template: editingTemplate) { result in
                if let existing = editingTemplate {
                    store.templates.update(result)
                } else {
                    store.templates.add(name: result.name, body: result.body, category: result.category)
                }
                showEditor = false
            }
        }
        .task { if store.templates.templates.isEmpty { store.templates.load() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prompt Templates")
                    .font(.title3.bold())
                Text("\(store.templates.templates.count) templates · click to insert into chat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Filter…", text: $searchText).textFieldStyle(.roundedBorder).frame(width: 200)
            }
        }
    }

    private func categorySection(_ category: String) -> some View {
        let templates = store.templates.templates(in: category).filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
        return Group {
            if !templates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(category)
                        .font(.headline)
                    ForEach(templates) { tpl in
                        TemplateRow(template: tpl,
                                    onInsert: { insertIntoChat(tpl) },
                                    onEdit: { editingTemplate = tpl; showEditor = true },
                                    onDelete: { store.templates.delete(tpl) })
                    }
                }
            }
        }
    }

    private func insertIntoChat(_ template: PromptTemplate) {
        store.bridge.send(template.body)
    }
}

private struct TemplateRow: View {
    let template: PromptTemplate
    let onInsert: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.callout.weight(.medium))
                Text(template.body.prefix(80))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button(action: onInsert) {
                Image(systemName: "arrow.up.message").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Insert into chat")
            Button(action: onEdit) {
                Image(systemName: "pencil").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Edit")
            Button(action: onDelete) {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct TemplateEditor: View {
    let template: PromptTemplate?
    let onSave: (PromptTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var promptBody: String = ""
    @State private var category: String = "General"

    var body: some View {
        VStack(spacing: 12) {
            Text(template == nil ? "New Template" : "Edit Template")
                .font(.title3.bold())

            HStack(spacing: 8) {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Category", text: $category).textFieldStyle(.roundedBorder).frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt body:").font(.caption.bold()).foregroundStyle(.secondary)
                TextEditor(text: $promptBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 300)
                    .padding(6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    let tpl = PromptTemplate(
                        id: template?.id ?? UUID().uuidString,
                        name: name.isEmpty ? "Untitled" : name,
                        body: promptBody,
                        category: category,
                        createdAt: template?.createdAt
                    )
                    onSave(tpl)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let tpl = template {
                name = tpl.name
                promptBody = tpl.body
                category = tpl.category
            }
        }
    }
}