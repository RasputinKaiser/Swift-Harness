import Foundation

/// Decoded record from `memory_fabric.py search --json`.
/// Mirrors the JSON shape — provenance is a nested object, evidence_path is optional.
struct MemoryRecord: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let body: String
    let tier: String
    let confidence: String?
    let status: String?
    let tags: [String]
    let scope: String
    let createdAt: String?
    let provenance: Provenance
    let verifyBeforeUse: Bool
    /// CLI's ranking score — higher is better-match. Used for sort.
    let score: Int?

    struct Provenance: Hashable, Codable {
        let type: String       // verified_command, source_backed_agent_run, etc.
        let detail: String
        let evidencePath: String?

        private enum CodingKeys: String, CodingKey {
            case type, detail
            case evidencePath = "evidence_path"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "?"
            detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
            evidencePath = try c.decodeIfPresent(String.self, forKey: .evidencePath)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encode(detail, forKey: .detail)
            try c.encodeIfPresent(evidencePath, forKey: .evidencePath)
        }

        init(type: String, detail: String, evidencePath: String?) {
            self.type = type
            self.detail = detail
            self.evidencePath = evidencePath
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, tier, confidence, status, tags, scope
        case createdAt = "created_at"
        case provenance
        case verifyBeforeUse = "verify_before_use"
        case score = "_score"
    }

    /// Best-effort date parse; falls back to nil.
    var date: Date? {
        guard let createdAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }

    var dateLabel: String {
        guard let date else { return "?" }
        return date.formatted(.relative(presentation: .named))
    }

    var tierTint: String {
        switch tier.lowercased() {
        case "learning": "blue"
        case "work": "purple"
        case "knowledge": "teal"
        default: "gray"
        }
    }
}

/// Filter/sort state for the Memory Fabric explorer.
enum MemorySort: String, CaseIterable, Hashable {
    case recent       // by createdAt desc
    case score        // by _score desc (CLI ranking)
    case confidence   // high > medium > low > unknown

    var label: String {
        switch self {
        case .recent: "Most recent"
        case .score: "Best match"
        case .confidence: "Highest confidence"
        }
    }
}