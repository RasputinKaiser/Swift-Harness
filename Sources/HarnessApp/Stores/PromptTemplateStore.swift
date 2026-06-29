import Foundation
import Observation

/// `@Observable` store for reusable prompt templates.
/// Reads/writes ~/.ncode/prompt_templates.json.
/// Templates can be inserted into the chat composer with one click.
@Observable
final class PromptTemplateStore {

    private(set) var templates: [PromptTemplate] = []
    private(set) var lastError: String?

    var savePath: URL {
        HarnessClient.ncodeDir.appendingPathComponent("prompt_templates.json", conformingTo: .text)
    }

    init() {}

    @MainActor
    func load() {
        guard let data = try? Data(contentsOf: savePath) else {
            // First run — seed with defaults
            templates = defaultTemplates
            save()
            return
        }
        if let arr = try? JSONDecoder().decode([PromptTemplate].self, from: data) {
            templates = arr
        } else {
            templates = defaultTemplates
        }
    }

    @MainActor
    func save() {
        do {
            let data = try JSONEncoder().encode(templates)
            try data.write(to: savePath)
            lastError = nil
        } catch {
            lastError = "save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    func add(name: String, body: String, category: String = "General") {
        let template = PromptTemplate(id: UUID().uuidString, name: name, body: body, category: category)
        templates.append(template)
        save()
    }

    @MainActor
    func update(_ template: PromptTemplate) {
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx] = template
            save()
        }
    }

    @MainActor
    func delete(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        save()
    }

    var categories: [String] {
        Array(Set(templates.map { $0.category })).sorted()
    }

    func templates(in category: String) -> [PromptTemplate] {
        templates.filter { $0.category == category }.sorted(by: { $0.name < $1.name })
    }

    private var defaultTemplates: [PromptTemplate] {
        [
            PromptTemplate(id: "tpl-improve", name: "Run /improve", body: "/improve", category: "Harness"),
            PromptTemplate(id: "tpl-brainstorm", name: "Run /brainstorm", body: "/brainstorm", category: "Harness"),
            PromptTemplate(id: "tpl-verify", name: "Run /verify", body: "/verify", category: "Harness"),
            PromptTemplate(id: "tpl-recall", name: "Recall memory", body: "/recall ", category: "Harness"),
            PromptTemplate(id: "tpl-run-tests", name: "Run harness tests", body: "Run the harness test suite and report results.", category: "Development"),
            PromptTemplate(id: "tpl-snapshot", name: "Take snapshot", body: "Take a harness snapshot before making changes.", category: "Safety"),
            PromptTemplate(id: "tpl-explain", name: "Explain this code", body: "Explain what this code does, focusing on the non-obvious parts:\n\n```\n\n```", category: "Development"),
            PromptTemplate(id: "tpl-review", name: "Code review", body: "Review the following changes for correctness, security, and clarity. Suggest concrete improvements:\n\n", category: "Development"),
        ]
    }
}

struct PromptTemplate: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var body: String
    var category: String
    var createdAt: String?

    init(id: String, name: String, body: String, category: String, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.body = body
        self.category = category
        self.createdAt = createdAt ?? ISO8601DateFormatter().string(from: Date())
    }
}