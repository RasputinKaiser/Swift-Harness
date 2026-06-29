import Foundation

/// Applies deterministic checks (Tier A from the eval-harness plan) to a
/// finished case run. No model calls — zero cost, zero flake.
///
/// `transcriptSequence` parses the tool_use names from the bridge's events
/// and verifies that one tool name (or regex) appears before another. This
/// is how the "Read before Edit" process check is graded with no model call.
enum EvalGrader {

    /// Grade a case run against its checks.
    /// - Parameters:
    ///   - checks: the case's grading checks, in declared order.
    ///   - sandboxURL: the cwd the case ran in (for file_exists/grep checks).
    ///   - toolSequence: the ordered list of tool names the agent invoked.
    /// - Returns: one Result per check, plus the weighted pass fraction.
    static func grade(_ checks: [EvalCheck],
                      sandboxURL: URL,
                      toolSequence: [String]) -> (results: [EvalCheck.Result], score: Double) {
        var results: [EvalCheck.Result] = []
        var weighted = 0.0
        var totalWeight = 0.0

        for check in checks {
            let r = apply(check, sandboxURL: sandboxURL, toolSequence: toolSequence)
            results.append(r)
            weighted += r.score * check.weight
            totalWeight += check.weight
        }
        let score = totalWeight > 0 ? weighted / totalWeight : 0
        return (results, score)
    }

    private static func apply(_ check: EvalCheck, sandboxURL: URL, toolSequence: [String]) -> EvalCheck.Result {
        switch check.kind {
        case .fileExists:
            return checkFileExists(arguments: check.arguments, sandboxURL: sandboxURL)
        case .fileMissing:
            return checkFileMissing(arguments: check.arguments, sandboxURL: sandboxURL)
        case .grep:
            return checkGrep(arguments: check.arguments, sandboxURL: sandboxURL)
        case .transcriptSequence:
            return checkTranscriptSequence(arguments: check.arguments, toolSequence: toolSequence)
        }
    }

    private static func checkFileExists(arguments: [String: String], sandboxURL: URL) -> EvalCheck.Result {
        guard let rel = arguments["path"], !rel.isEmpty else {
            return EvalCheck.Result(score: 0, evidence: "missing 'path' argument", passed: false)
        }
        let url = sandboxURL.appendingPathComponent(rel, conformingTo: .text)
        let exists = FileManager.default.fileExists(atPath: url.path)
        return EvalCheck.Result(
            score: exists ? 1.0 : 0.0,
            evidence: "\(rel) \(exists ? "exists" : "missing")",
            passed: exists
        )
    }

    private static func checkFileMissing(arguments: [String: String], sandboxURL: URL) -> EvalCheck.Result {
        guard let rel = arguments["path"], !rel.isEmpty else {
            return EvalCheck.Result(score: 0, evidence: "missing 'path' argument", passed: false)
        }
        let url = sandboxURL.appendingPathComponent(rel, conformingTo: .text)
        let absent = !FileManager.default.fileExists(atPath: url.path)
        return EvalCheck.Result(
            score: absent ? 1.0 : 0.0,
            evidence: "\(rel) \(absent ? "absent (correct)" : "present (wrong)")",
            passed: absent
        )
    }

    private static func checkGrep(arguments: [String: String], sandboxURL: URL) -> EvalCheck.Result {
        guard let rel = arguments["path"], let pattern = arguments["pattern"] else {
            return EvalCheck.Result(score: 0, evidence: "missing 'path' or 'pattern'", passed: false)
        }
        let url = sandboxURL.appendingPathComponent(rel, conformingTo: .text)
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return EvalCheck.Result(score: 0, evidence: "could not read \(rel)", passed: false)
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return EvalCheck.Result(score: 0, evidence: "invalid regex: \(pattern)", passed: false)
        }
        let range = NSRange(content.startIndex..., in: content)
        let matched = regex.firstMatch(in: content, options: [], range: range) != nil
        return EvalCheck.Result(
            score: matched ? 1.0 : 0.0,
            evidence: "pattern \(pattern) \(matched ? "matched" : "not found") in \(rel)",
            passed: matched
        )
    }

    /// Verify tool `first` (or a regex matching the tool name) is invoked
    /// before any tool matching `before`. Used for the "Read before Edit"
    /// process check.
    private static func checkTranscriptSequence(arguments: [String: String], toolSequence: [String]) -> EvalCheck.Result {
        guard let beforePattern = arguments["before"] else {
            return EvalCheck.Result(score: 0, evidence: "missing 'before' argument", passed: false)
        }
        let firstTarget = arguments["first"] ?? ""
        guard let firstRegex = try? NSRegularExpression(pattern: firstTarget, options: []),
              let beforeRegex = try? NSRegularExpression(pattern: beforePattern, options: []) else {
            return EvalCheck.Result(score: 0, evidence: "invalid regex", passed: false)
        }
        var firstSeenIdx: Int?
        var beforeSeenIdx: Int?
        for (i, tool) in toolSequence.enumerated() {
            let r = NSRange(tool.startIndex..., in: tool)
            if firstSeenIdx == nil, firstRegex.firstMatch(in: tool, options: [], range: r) != nil {
                firstSeenIdx = i
            }
            if beforeSeenIdx == nil, beforeRegex.firstMatch(in: tool, options: [], range: r) != nil {
                beforeSeenIdx = i
            }
        }
        // Pass if first appeared before "before", OR "before" never appeared.
        // The intent: the agent must read/verify first; if it didn't edit at all that's still a pass.
        if let b = beforeSeenIdx {
            if let f = firstSeenIdx {
                let passed = f < b
                return EvalCheck.Result(
                    score: passed ? 1.0 : 0.0,
                    evidence: "first(\(firstTarget)) at \(f), before(\(beforePattern)) at \(b)",
                    passed: passed
                )
            }
            return EvalCheck.Result(
                score: 0,
                evidence: "before-pattern matched at \(b) but first(\(firstTarget)) never appeared",
                passed: false
            )
        }
        // "before" never matched — agent didn't violate the rule.
        return EvalCheck.Result(
            score: 1.0,
            evidence: "before-pattern (\(beforePattern)) never matched; sequence ok",
            passed: true
        )
    }
}