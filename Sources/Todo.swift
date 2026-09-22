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
        case id, title, horizon, bucket, isDone, isStarred, createdAt
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
