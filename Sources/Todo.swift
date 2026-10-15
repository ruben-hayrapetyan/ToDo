import Foundation

/// Short term is the sectioned view; long term is a single flat list.
enum Horizon: String, Codable, CaseIterable, Identifiable {
    case shortTerm
    case longTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortTerm: return "Short Term"
        case .longTerm:  return "Long Term"
        }
    }
}

/// What the window shows: one horizon, or every dated task from both in the
/// order they fall due. The raw values of the first two match `Horizon`, so the
/// saved tab from before the due page existed still reads back.
enum Page: String, CaseIterable, Identifiable {
    case shortTerm
    case longTerm
    case due

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortTerm: return "Short Term"
        case .longTerm:  return "Long Term"
        case .due:       return "Due"
        }
    }

    /// "every short-term task", "every dated task".
    var adjective: String {
        switch self {
        case .shortTerm: return "short-term"
        case .longTerm:  return "long-term"
        case .due:       return "dated"
        }
    }

    func contains(_ todo: Todo) -> Bool {
        switch self {
        case .shortTerm: return todo.horizon == .shortTerm
        case .longTerm:  return todo.horizon == .longTerm
        case .due:       return todo.dueDate != nil
        }
    }
}

/// The sections of the short-term view, in display order.
enum Bucket: String, Codable, CaseIterable, Identifiable {
    case readings
    case assignments
    case emails
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readings:    return "Readings"
        case .assignments: return "Assignments"
        case .emails:      return "Emails"
        case .other:       return "Other"
        }
    }

    /// Menu wording for the ⌘-number shortcut that jumps to this section.
    var singular: String {
        switch self {
        case .readings:    return "Reading"
        case .assignments: return "Assignment"
        case .emails:      return "Email"
        case .other:       return "Other Task"
        }
    }

    /// Placeholder for that section's own add field.
    var prompt: String {
        switch self {
        case .readings:    return "Add a reading…"
        case .assignments: return "Add an assignment…"
        case .emails:      return "Add an email…"
        case .other:       return "Add anything else…"
        }
    }
}

/// Where a task lives. Only short-term tasks have a section, so long-term ones
/// cannot carry a meaningless bucket.
enum Place: Equatable {
    case shortTerm(Bucket)
    case longTerm

    var horizon: Horizon {
        switch self {
        case .shortTerm: return .shortTerm
        case .longTerm:  return .longTerm
        }
    }
}

/// A single task.
///
/// On disk the place is still written as flat `horizon` and `bucket` keys, so
/// the file stays easy to read with jq. `bucket` is left out for long-term tasks.
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var place: Place
    var isDone: Bool
    var isStarred: Bool
    var createdAt: Date
    /// When the task is due, or nil for none.
    var dueDate: Date?
    /// How far along an unfinished task is, in quarters: 0 (not started) to 3.
    /// Kept when the task is ticked, so unticking puts it back where it was.
    var progress: Int = 0

    static let quarters = 0...3

    var horizon: Horizon { place.horizon }

    /// The short-term section, or nil for a long-term task.
    var bucket: Bucket? {
        if case .shortTerm(let bucket) = place { return bucket }
        return nil
    }

    init(title: String, place: Place) {
        self.id = UUID()
        self.title = title
        self.place = place
        self.isDone = false
        self.isStarred = false
        self.createdAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, horizon, bucket, isDone, isStarred, createdAt, dueDate, progress
    }

    /// Decoded by hand so task files written by earlier versions — which had no
    /// bucket, star, or horizon — still load instead of throwing the whole list
    /// away. Anything saved before horizons existed counts as short term, and
    /// the placeholder bucket older versions wrote on long-term tasks is dropped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        let horizon = try c.decodeIfPresent(Horizon.self, forKey: .horizon) ?? .shortTerm
        switch horizon {
        case .shortTerm:
            place = .shortTerm(try c.decodeIfPresent(Bucket.self, forKey: .bucket) ?? .assignments)
        case .longTerm:
            place = .longTerm
        }
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        let quarters = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        progress = min(max(quarters, Self.quarters.lowerBound), Self.quarters.upperBound)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(horizon, forKey: .horizon)
        try c.encodeIfPresent(bucket, forKey: .bucket)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(isStarred, forKey: .isStarred)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        if progress != 0 { try c.encode(progress, forKey: .progress) }
    }
}

/// How a due date reads at a given moment.
enum DueState: Equatable {
    /// A day or more away: show the date itself.
    case later(Date)
    /// Under a day left: seconds remaining, counting down to 0.
    case countdown(TimeInterval)
    /// Past due: seconds since the deadline, counting up from 0.
    case overdue(TimeInterval)

    static let day: TimeInterval = 24 * 60 * 60

    init(due: Date, now: Date) {
        let remaining = due.timeIntervalSince(now)
        if remaining <= 0 {
            self = .overdue(-remaining)
        } else if remaining < Self.day {
            self = .countdown(remaining)
        } else {
            self = .later(due)
        }
    }

    /// "4:07:09". Countdowns are always under a day, so hours are the top unit.
    /// Rounds up, so the last second before the deadline shows 0:00:01 and the
    /// deadline itself flips to overdue.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }

    /// How long ago the deadline was, in weeks, days, hours, minutes and
    /// seconds, keeping only the three largest units from the biggest one that
    /// is not zero: "1w 1d 3h", "3d 4h 5m", "1h 0m 5s", "5m 6s", "42s". Whole
    /// seconds, rounded down, so it starts at 0s.
    static func elapsed(_ seconds: TimeInterval) -> String {
        var rest = Int(seconds.rounded(.down))
        let sizes = [("w", 604_800), ("d", 86_400), ("h", 3600), ("m", 60), ("s", 1)]
        var units: [(String, Int)] = []
        for (name, size) in sizes {
            units.append((name, rest / size))
            rest %= size
        }
        let first = units.firstIndex { $0.1 > 0 } ?? units.count - 1
        return units[first...].prefix(3).map { "\($0.1)\($0.0)" }.joined(separator: " ")
    }

    /// The text shown on the task row.
    var text: String {
        switch self {
        case .later(let date):
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        case .countdown(let remaining):
            return Self.clock(remaining)
        case .overdue(let elapsed):
            return "+" + Self.elapsed(elapsed)
        }
    }

    /// The next moment after `now` when the text reads differently, so a row
    /// redraws when its label changes rather than every second. A date waits
    /// until it turns into a countdown; the countdown and the first overdue day
    /// change every second, then every minute, and past a week every hour.
    /// Every step lands a whole number of seconds from the deadline, so rows
    /// due on whole seconds all redraw in the same pass.
    static func nextChange(due: Date, after now: Date) -> Date {
        let remaining = due.timeIntervalSince(now)
        let before: TimeInterval   // seconds before the deadline; negative once past
        if remaining >= day {
            before = day - 1
        } else if remaining > 0 {
            // clock() rounds up, so the text changes as each whole second is reached.
            before = remaining.rounded(.up) - 1
        } else {
            let elapsed = -remaining
            let step: TimeInterval = elapsed < day ? 1 : elapsed < 7 * day ? 60 : 3600
            before = -((elapsed / step).rounded(.down) + 1) * step
        }
        let next = due.addingTimeInterval(-before)
        // Floating-point rounding must never leave the schedule standing still.
        return next > now ? next : now.addingTimeInterval(1)
    }
}

/// Which tasks the window is currently showing.
enum Filter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case starred = "Starred"
    case done = "Done"

    var id: String { rawValue }

    func matches(_ todo: Todo) -> Bool {
        switch self {
        case .all:     return true
        case .active:  return !todo.isDone
        case .starred: return todo.isStarred
        case .done:    return todo.isDone
        }
    }
}

/// Reads a due date out of what the person typed: "3pm", "tomorrow 5pm",
/// "fri 9:30am", "9/25", "in 2 hours", "90m", "noon", "eod".
enum DueParser {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        if let later = duration(text) { return now.addingTimeInterval(later) }

        func at(_ hour: Int, _ minute: Int, addingDays days: Int = 0) -> Date? {
            let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }

        // Words the system parser doesn't know.
        switch text {
        case "eod", "end of day": return at(23, 59)
        case "noon":              return at(12, 0).map { $0 > now ? $0 : at(12, 0, addingDays: 1)! }
        case "midnight":          return at(23, 59)
        default: break
        }

        guard let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              var date = match.date else { return nil }

        // "friday" alone comes back as noon. A day with no time means the day itself, so
        // it is due at the end of it.
        let hasTime = text.range(of: #"\d\s*(a|p)m?\b|\d:\d\d|noon|midnight|\bat\s+\d"#,
                                 options: .regularExpression) != nil
        if !hasTime { date = at(23, 59, addingDays: calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)).day ?? 0) ?? date }

        // A bare time that has already gone today means tomorrow.
        if date <= now, calendar.isDate(date, inSameDayAs: now), !text.contains("today") {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    /// "2h", "30 min", "in 3 days", "1d 4h".
    private static func duration(_ text: String) -> TimeInterval? {
        var rest = text
        if rest.hasPrefix("in ") { rest.removeFirst(3) }
        let pattern = #"(\d+(?:\.\d+)?)\s*(d|day|days|h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let whole = NSRange(rest.startIndex..., in: rest)
        let matches = regex.matches(in: rest, range: whole)
        guard !matches.isEmpty else { return nil }

        // Everything must be part of a duration, so "5 min past 3pm" isn't misread.
        let leftover = regex.stringByReplacingMatches(in: rest, range: whole, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
        guard leftover.isEmpty || leftover == "and" else { return nil }

        var total: TimeInterval = 0
        for m in matches {
            guard let n = Double(rest[Range(m.range(at: 1), in: rest)!]) else { return nil }
            let unit = rest[Range(m.range(at: 2), in: rest)!]
            total += n * (unit.hasPrefix("d") ? 86_400 : unit.hasPrefix("h") ? 3600 : 60)
        }
        return total
    }
}
