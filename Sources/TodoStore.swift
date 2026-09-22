import Combine
import Foundation

/// Owns the task list and keeps it on disk.
///
/// Tasks live in ~/Documents/Todo List/todos.json and are rewritten atomically
/// after every change, so a crash can't leave a half file.
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [Todo] = []

    /// What the last "unstar all" removed, so the same control can put it back.
    /// Session-only and deliberately not saved: a relaunch starts clean.
    @Published private(set) var unstarUndo: UnstarUndo?

    /// Something the person needs to know about the task file — it could not be
    /// read, was set aside, or is not being saved. Shown as a banner.
    @Published private(set) var problem: String?

    struct UnstarUndo: Equatable {
        let horizon: Horizon
        let ids: Set<UUID>
    }

    /// Set by the window so every change lands on Edit ▸ Undo. Optional because
    /// tests and the design renderer run without one.
    var undoManager: UndoManager?

    private let fileURL: URL

    /// True when the file exists but could not be read or set aside. Saving then
    /// would replace tasks we never loaded, so nothing is written at all.
    private(set) var writesBlocked = false

    /// Whether `problem` came from a failed save, so the next good save can
    /// clear it without hiding a load problem.
    private var problemIsSaveFailure = false

    /// Where tasks live: ~/Documents/Todo List/todos.json.
    ///
    /// Documents rather than Application Support because that folder is hidden
    /// and protected — Finder will not show it and folder pickers often refuse
    /// it outright, which made the file hard to reach from other tools.
    static var defaultStoreURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("Todo List", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    /// The pre-2026-09-02 location, kept only so existing tasks can be moved.
    static var legacyStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Todo List", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    /// Moves an older task file to the new location, once. Does nothing if the
    /// destination already exists, so it can never overwrite live tasks.
    @discardableResult
    static func migrate(from legacy: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path),
              fm.fileExists(atPath: legacy.path) else { return false }
        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: legacy, to: destination)
        } catch {
            // A move can fail across volumes; a copy still gets the tasks across.
            guard (try? fm.copyItem(at: legacy, to: destination)) != nil else { return false }
        }
        // Tidy up the old folder, but only if nothing else is in it.
        let oldFolder = legacy.deletingLastPathComponent()
        if let left = try? fm.contentsOfDirectory(atPath: oldFolder.path), left.isEmpty {
            try? fm.removeItem(at: oldFolder)
        }
        return true
    }

    /// `storeURL` exists so tests can point at a scratch file; the app always
    /// uses the default location.
    init(storeURL: URL? = nil) {
        if let storeURL = storeURL {
            self.fileURL = storeURL
        } else {
            Self.migrate(from: Self.legacyStoreURL, to: Self.defaultStoreURL)
            self.fileURL = Self.defaultStoreURL
        }
        // Always, not just for the default path: without the folder every save
        // fails and the tasks are never written.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        load()
    }

    // MARK: - Derived values

    func remainingCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon && !$0.isDone }.count
    }

    func totalCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon }.count
    }

    func doneCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon && $0.isDone }.count
    }

    func starredCount(in horizon: Horizon) -> Int {
        todos.filter { $0.horizon == horizon && $0.isStarred }.count
    }

    /// Unfinished tasks left in one short-term section, for its header badge.
    func remainingCount(in bucket: Bucket) -> Int {
        todos.filter { $0.place == .shortTerm(bucket) && !$0.isDone }.count
    }

    /// The tasks to draw in one short-term section.
    func items(in bucket: Bucket, filter: Filter) -> [Todo] {
        todos
            .filter { $0.place == .shortTerm(bucket) && filter.matches($0) }
            .sorted(by: Self.inOrder)
    }

    /// The long-term view is one flat list, so it ignores buckets entirely.
    func longTermItems(filter: Filter) -> [Todo] {
        todos
            .filter { $0.place == .longTerm && filter.matches($0) }
            .sorted(by: Self.inOrder)
    }

    /// Everything on screen for one view, top to bottom — the order the arrow
    /// keys walk through.
    func visibleItems(in horizon: Horizon, filter: Filter) -> [Todo] {
        switch horizon {
        case .shortTerm: return Bucket.allCases.flatMap { items(in: $0, filter: filter) }
        case .longTerm:  return longTermItems(filter: filter)
        }
    }

    /// Alphabetical, with finished tasks moved to the bottom. Stars do not
    /// affect the order.
    ///
    /// The comparison is `localizedStandardCompare` — the same one Finder uses —
    /// so case is ignored and embedded numbers sort as numbers ("13.2" before
    /// "13.10", not after). Equal titles fall back to age, then id, so two
    /// identical tasks never swap places between redraws.
    static func inOrder(_ a: Todo, _ b: Todo) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        switch a.title.localizedStandardCompare(b.title) {
        case .orderedAscending:  return true
        case .orderedDescending: return false
        case .orderedSame:
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    // MARK: - Mutations

    func add(_ rawTitle: String, to bucket: Bucket) {
        append(rawTitle, place: .shortTerm(bucket))
    }

    func addLongTerm(_ rawTitle: String) {
        append(rawTitle, place: .longTerm)
    }

    private func append(_ rawTitle: String, place: Place) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        change("Add Task") { $0.append(Todo(title: title, place: place)) }
    }

    func toggle(_ todo: Todo) {
        update(todo, "Mark as \(todo.isDone ? "Not Done" : "Done")") { $0.isDone.toggle() }
    }

    func toggleStar(_ todo: Todo) {
        // Once a star is set by hand, "restore" would fight the user.
        unstarUndo = nil
        update(todo, todo.isStarred ? "Remove Star" : "Star") { $0.isStarred.toggle() }
    }

    func rename(_ todo: Todo, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty rename means "delete", matching how most task apps behave.
        if title.isEmpty {
            delete(todo)
        } else if title != todo.title {
            update(todo, "Rename") { $0.title = title }
        }
    }

    func delete(_ todo: Todo) {
        change("Delete Task") { list in list.removeAll { $0.id == todo.id } }
    }

    /// Takes the star off every task in one horizon, remembering which ones so
    /// `restoreStars` can undo it. Scoped like clearCompleted: the view you are
    /// not looking at is never touched.
    func unstarAll(in horizon: Horizon) {
        let ids = Set(todos.filter { $0.horizon == horizon && $0.isStarred }.map(\.id))
        guard !ids.isEmpty else { return }
        change("Unstar All") { list in
            for i in list.indices where ids.contains(list[i].id) {
                list[i].isStarred = false
            }
        }
        unstarUndo = UnstarUndo(horizon: horizon, ids: ids)
    }

    /// Puts back exactly the stars the last `unstarAll` removed. Tasks deleted
    /// in the meantime are simply skipped.
    func restoreStars() {
        guard let undo = unstarUndo else { return }
        change("Restore Stars") { list in
            for i in list.indices where undo.ids.contains(list[i].id) {
                list[i].isStarred = true
            }
        }
        unstarUndo = nil
    }

    /// Scoped to the horizon on screen, so clearing one view never touches the other.
    func clearCompleted(in horizon: Horizon) {
        change("Clear Completed") { list in list.removeAll { $0.horizon == horizon && $0.isDone } }
    }

    func dismissProblem() {
        problem = nil
        problemIsSaveFailure = false
    }

    private func update(_ todo: Todo, _ actionName: String, _ edit: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        change(actionName) { edit(&$0[i]) }
    }

    /// The one path every mutation takes: apply it, save, and register an undo
    /// that puts the whole list back. Snapshots are cheap at this size and can't
    /// drift out of step with the change they reverse.
    private func change(_ actionName: String, _ edit: (inout [Todo]) -> Void) {
        let before = todos
        edit(&todos)
        guard todos != before else { return }
        save()
        registerUndo(restoring: before, actionName: actionName)
    }

    private func registerUndo(restoring snapshot: [Todo], actionName: String) {
        guard let undoManager = undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            let current = store.todos
            store.todos = snapshot
            // Undo can bring back stars the restore control no longer knows about.
            store.unstarUndo = nil
            store.save()
            store.registerUndo(restoring: current, actionName: actionName)   // redo
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Persistence

    /// One task that failed to decode must not take the rest of the list with it.
    private struct LossyTodo: Decodable {
        let todo: Todo?
        init(from decoder: Decoder) throws { todo = try? Todo(from: decoder) }
    }

    private func load() {
        let fm = FileManager.default
        // No file yet is the normal first launch, not an error.
        guard fm.fileExists(atPath: fileURL.path) else { return }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // Most often macOS denied access to Documents. The tasks are still
            // there, so saving an empty list over them is the one thing not to do.
            writesBlocked = true
            problem = "Couldn't open \(fileURL.path) (\(error.localizedDescription)). "
                + "Nothing will be saved until this is fixed, so the file is left untouched. "
                + "Check System Settings ▸ Privacy & Security ▸ Files and Folders, then relaunch."
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let entries = try? decoder.decode([LossyTodo].self, from: data) {
            todos = entries.compactMap(\.todo)
            let skipped = entries.count - todos.count
            if skipped > 0 {
                // The next save would drop the bad entries, so keep the original.
                if let backup = setAside(copy: true) {
                    problem = "\(skipped) task\(skipped == 1 ? "" : "s") couldn't be read and "
                        + "\(skipped == 1 ? "was" : "were") left out. The original file is saved as \(backup.lastPathComponent)."
                } else {
                    writesBlocked = true
                    problem = "\(skipped) task\(skipped == 1 ? "" : "s") couldn't be read, and a backup "
                        + "couldn't be made, so nothing will be saved to avoid losing them."
                }
            }
            return
        }

        // Not a task list at all. Move it out of the way rather than overwrite it.
        if let aside = setAside(copy: false) {
            problem = "Your task file couldn't be read, so it was moved to "
                + "\(aside.lastPathComponent) in the same folder and you're starting with an empty list. "
                + "Nothing in it was deleted."
        } else {
            writesBlocked = true
            problem = "Your task file couldn't be read or moved aside, so nothing will be saved "
                + "until it's fixed. The file is at \(fileURL.path)."
        }
    }

    /// Moves or copies the task file to a timestamped name beside it.
    private func setAside(copy: Bool) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("todos.unreadable-\(stamp).json")
        do {
            if copy {
                try FileManager.default.copyItem(at: fileURL, to: destination)
            } else {
                try FileManager.default.moveItem(at: fileURL, to: destination)
            }
            return destination
        } catch {
            return nil
        }
    }

    private func save() {
        guard !writesBlocked else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let data = try encoder.encode(todos)
            try data.write(to: fileURL, options: .atomic)
            if problemIsSaveFailure { dismissProblem() }
        } catch {
            if problem == nil || problemIsSaveFailure {
                problem = "Couldn't save your tasks (\(error.localizedDescription)). "
                    + "Recent changes are only in memory and will be lost when the app quits."
                problemIsSaveFailure = true
            }
        }
    }
}
