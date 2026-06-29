import Foundation

/// Native 5-field cron expression parser with next-fire computation.
///
/// No third-party deps — fully self-contained. Handles `*`, comma lists,
/// ranges (`1-5`), and step values (`*/15`, `1-10/2`). Used by
/// ScheduledTaskRow to show next-fire timestamps and human descriptions.
///
/// Algorithm: walk forward minute-by-minute from "now+1" until all five
/// fields match. Bounded iteration — capped at 366 days to guarantee
/// termination on impossible schedules (e.g. Feb 30).
struct CronExpression: Equatable {
    let minute: CronField
    let hour: CronField
    let dayOfMonth: CronField
    let month: CronField
    let dayOfWeek: CronField
    let raw: String

    /// Parse a 5-field cron string. Returns nil on malformed input.
    static func parse(_ raw: String) -> CronExpression? {
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 5 else { return nil }
        guard let m = CronField.parse(parts[0], max: 59),
              let h = CronField.parse(parts[1], max: 23),
              let dom = CronField.parse(parts[2], max: 31),
              let mon = CronField.parse(parts[3], max: 12),
              let dow = CronField.parse(parts[4], max: 6) else {
            return nil
        }
        return CronExpression(minute: m, hour: h, dayOfMonth: dom, month: mon,
                              dayOfWeek: dow, raw: raw)
    }

    /// Compute the next firing time strictly after `from`. Returns nil if
    /// nothing matches within 366 days (impossible schedule like Feb 30).
    func nextFire(after from: Date) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.second = 0
        var probe = cal.nextDate(after: from, matching: comps, matchingPolicy: .nextTime) ?? from
        let deadline = cal.date(byAdding: .day, value: 366, to: from) ?? from
        var iterations = 0
        let max = 366 * 24 * 60 // ~525k iterations max

        while probe < deadline && iterations < max {
            iterations += 1
            let dc = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: probe)
            // weekday: 1=Sunday in Calendar. Cron 0 or 7 = Sunday. Map to 0-6.
            let cronDow = (dc.weekday ?? 1) - 1
            if minute.matches(dc.minute ?? 0)
                && hour.matches(dc.hour ?? 0)
                && month.matches(dc.month ?? 0)
                && dayOfMonth.matches(dc.day ?? 0)
                && dayOfWeek.matches(cronDow) {
                return probe
            }
            guard let next = cal.date(byAdding: .minute, value: 1, to: probe) else { break }
            probe = next
        }
        return nil
    }

    /// Human-readable description ("every 5 min", "weekdays 9:17 AM", etc.).
    var humanDescription: String {
        if minute.isStar && hour.isStar && dayOfMonth.isStar && month.isStar && dayOfWeek.isStar {
            return "every minute"
        }
        // */N on minute, */N on hour pattern
        if month.isStar && dayOfMonth.isStar {
            if let step = minute.stepValue, hour.isStar {
                return "every \(step) min"
            }
            if minute.isSingle, let step = hour.stepValue {
                return "every \(step) hours at :\(String(format: "%02d", minute.firstValue))"
            }
            if minute.isSingle && hour.isSingle {
                let h = hour.firstValue
                let m = minute.firstValue
                let isWeekday = dayOfWeek.matchesRange(1...5)
                let dayLabel: String
                if isWeekday {
                    dayLabel = "weekdays"
                } else if dayOfWeek.isStar {
                    dayLabel = "daily"
                } else {
                    dayLabel = dayOfWeek.shortLabel
                }
                return "\(dayLabel) \(formatTime(h: h, m: m))"
            }
            if let step = minute.stepValue, hour.isSingle {
                return "hourly at :\(String(format: "%02d", minute.firstValue)) (every \(step) min)"
            }
        }
        // Specific month/day patterns
        var parts: [String] = []
        if !month.isStar { parts.append("month \(month.shortLabel)") }
        if !dayOfMonth.isStar { parts.append("day \(dayOfMonth.shortLabel)") }
        if !hour.isStar { parts.append(formatTime(h: hour.firstValue, m: minute.firstValue)) }
        if !dayOfWeek.isStar { parts.append(dayOfWeek.shortLabel) }
        if parts.isEmpty {
            return raw
        }
        return parts.joined(separator: " ")
    }

    private func formatTime(h: Int, m: Int) -> String {
        let ampm = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(String(format: "%02d", m)) \(ampm)"
    }
}

/// A single cron field (minute, hour, etc.) with flexible matching.
struct CronField: Equatable {
    let values: Set<Int>
    let raw: String

    var isStar: Bool { raw == "*" }
    var isSingle: Bool { values.count == 1 && raw != "*" }
    var firstValue: Int { values.min() ?? 0 }

    var stepValue: Int? {
        // Matches "*/N" or "low-high/N" — extract N if raw contains "/"
        guard raw.contains("/") else { return nil }
        return Int(raw.split(separator: "/").last ?? "")
    }

    var isRange: Bool { raw.contains("-") && !raw.contains("/") }

    func matches(_ v: Int) -> Bool { values.contains(v) }

    /// True if values are exactly the integers in `range`.
    func matchesRange(_ range: ClosedRange<Int>) -> Bool {
        let expected = Set(range)
        return values == expected
    }

    var shortLabel: String {
        if isStar { return "*" }
        let sorted = values.sorted()
        if sorted.count > 4 {
            return raw
        }
        return sorted.map(String.init).joined(separator: ",")
    }

    static func parse(_ s: String, max: Int) -> CronField? {
        if s == "*" {
            return CronField(values: Set(0...max), raw: s)
        }
        // Step: */N or A-B/N
        if s.contains("/") {
            let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 2, let step = Int(parts[1]), step > 0 else { return nil }
            let rangePart = parts[0]
            let lo, hi: Int
            if rangePart == "*" {
                lo = 0; hi = max
            } else if rangePart.contains("-") {
                let r = rangePart.split(separator: "-").map(String.init)
                guard r.count == 2, let l = Int(r[0]), let h = Int(r[1]) else { return nil }
                lo = l; hi = h
            } else if let v = Int(rangePart) {
                lo = v; hi = max
            } else {
                return nil
            }
            var set = Set<Int>()
            var i = lo
            while i <= hi { set.insert(i); i += step }
            return CronField(values: set, raw: s)
        }
        // Comma list
        var set = Set<Int>()
        for part in s.split(separator: ",") {
            let p = String(part)
            if p.contains("-") {
                let r = p.split(separator: "-").map(String.init)
                guard r.count == 2, let lo = Int(r[0]), let hi = Int(r[1]),
                      lo <= hi, lo >= 0, hi <= max else { return nil }
                set.formUnion(lo...hi)
            } else if let v = Int(p) {
                guard v >= 0 && v <= max else { return nil }
                set.insert(v)
            } else if p == "7" && max == 6 {
                set.insert(0)
            } else {
                return nil
            }
        }
        if set.isEmpty { return nil }
        return CronField(values: set, raw: s)
    }
}