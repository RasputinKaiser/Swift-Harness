import Foundation

/// A single evaluation case: a synthetic prompt with a known-good outcome
/// and a deterministic grading rubric.
///
/// Cases live at `~/.ncode/eval/cases/<id>.json`. Each case is run against the
/// live NCode model config via NCodeBridge; the transcript is graded by a
/// list of deterministic checkers (file_exists, grep, transcript_sequence).
///
/// This is the Swift-native Phase 1 of the eval harness — a minimal,
/// self-contained, unit-testable core. LLM-as-judge (Tier C in the original
/// plan) is explicitly deferred until deterministic graders prove insufficient.
struct EvalCase: Identifiable, Codable, Hashable {
    let id: String
    let version: Int
    let tier: Tier
    let difficulty: Difficulty
    let prompt: String
    let timeoutSeconds: Int
    let grading: [EvalCheck]
    let passThreshold: Double
    let tags: [String]

    enum Tier: String, Codable, CaseIterable {
        case process
        case quality
    }

    enum Difficulty: String, Codable, CaseIterable {
        case trivial, moderate, hard
    }

    /// Weighted pass fraction across all checks. Each check carries its own
    /// weight (default 1.0); a check result contributes weight * score to
    /// the numerator and weight to the denominator.
    func score(for results: [EvalCheck.Result]) -> Double {
        guard !grading.isEmpty else { return 0 }
        var weighted = 0.0
        var totalWeight = 0.0
        for (i, check) in grading.enumerated() {
            let r = results.indices.contains(i) ? results[i] : EvalCheck.Result(score: 0, evidence: "missing", passed: false)
            weighted += r.score * check.weight
            totalWeight += check.weight
        }
        return totalWeight > 0 ? weighted / totalWeight : 0
    }

    var passed: Bool { false } // Computed at runtime from results, not stored.
}

/// A single deterministic check applied to a finished case run.
struct EvalCheck: Codable, Hashable {
    let kind: Kind
    let weight: Double
    let arguments: [String: String]

    enum Kind: String, Codable, CaseIterable {
        case fileExists
        case fileMissing
        case grep
        case transcriptSequence
    }

    init(kind: Kind, arguments: [String: String], weight: Double = 1.0) {
        self.kind = kind
        self.arguments = arguments
        self.weight = weight
    }

    /// Result of applying this check to a finished case run.
    struct Result: Codable, Hashable {
        let score: Double
        let evidence: String
        let passed: Bool
    }
}

/// A finished or in-progress run of one case.
struct EvalRun: Identifiable, Codable {
    let id: UUID
    let caseId: String
    let caseVersion: Int
    let startedAt: Date
    let finishedAt: Date?
    let score: Double?
    let passed: Bool?
    let sandboxURL: URL?
    let checkResults: [EvalCheck.Result]
    let toolCount: Int
    let model: String?
    let errorMessage: String?

    init(caseId: String, caseVersion: Int, model: String? = nil) {
        self.id = UUID()
        self.caseId = caseId
        self.caseVersion = caseVersion
        self.startedAt = Date()
        self.finishedAt = nil
        self.score = nil
        self.passed = nil
        self.sandboxURL = nil
        self.checkResults = []
        self.toolCount = 0
        self.model = model
        self.errorMessage = nil
    }

    init(caseId: String, caseVersion: Int, model: String?, sandboxURL: URL,
         finishedAt: Date, score: Double, passed: Bool,
         checkResults: [EvalCheck.Result], toolCount: Int, errorMessage: String?) {
        self.id = UUID()
        self.caseId = caseId
        self.caseVersion = caseVersion
        self.startedAt = Date()
        self.finishedAt = finishedAt
        self.score = score
        self.passed = passed
        self.sandboxURL = sandboxURL
        self.checkResults = checkResults
        self.toolCount = toolCount
        self.model = model
        self.errorMessage = errorMessage
    }
}