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
        let page: Page
        let ids: Set<UUID>
    }

    /// Set by the window so every change lands on Edit ▸ Undo. Optional because
    /// tests and the design renderer run without one.
    ///
    /// Each step keeps a copy of the whole list, and the app runs for days at a
    /// time as a login item, so the history is capped. The cap covers the
    /// window's text fields too, which share this manager.
    var undoManager: UndoManager? {
        didSet { undoManager?.levelsOfUndo = Self.undoLevels }
    }

    static let undoLevels = 100

    private let fileURL: URL

    /// True when the file exists but could not be read or set aside. Saving then
    /// would replace tasks we never loaded, so nothing is written at all.
    private(set) var writesBlocked = false

    /// Whether `problem` came from a failed save, so the next good save can
    /// clear it without hiding a load problem.
    private var problemIsSaveFailure = false

    /// The problem a failed save took the banner from. Losing edits is the more
    /// urgent news, but the earlier one comes back once it is dealt with.
    private var coveredProblem: String?

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
        let isDefaultStore = storeURL == nil
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
        // Only the real app takes daily snapshots; a test's scratch store
        // shouldn't leave files behind next to it.
        if isDefaultStore {
            snapshotForToday()
        }
    }

    // MARK: - Daily snapshots

    /// ~/Documents/Todo List/saves — one JSON file per day, named by date.
    private var savesDirectoryURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("saves", isDirectory: true)
    }

    private static let snapshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        // A fixed format needs the POSIX locale, or some locales write the
        // digits in another script.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Writes today's snapshot the first time the app launches that day and
    /// removes the snapshots left from earlier days, so the saves folder only
    /// ever holds today's copy.
    private func snapshotForToday() {
        // A list that didn't load cleanly is not the person's tasks. Replacing
        // the last good snapshot with it would throw away the one copy that
        // could bring them back.
        guard problem == nil, !writesBlocked else { return }

        let fm = FileManager.default
        let todayName = Self.snapshotDateFormatter.string(from: Date()) + ".json"
        let todayURL = savesDirectoryURL.appendingPathComponent(todayName)
        guard !fm.fileExists(atPath: todayURL.path) else { return }

        try? fm.createDirectory(at: savesDirectoryURL, withIntermediateDirectories: true)
        // Write first, so a failed write never leaves the folder with no snapshot.
        guard let data = try? Self.encode(todos),
              (try? data.write(to: todayURL, options: .atomic)) != nil else { return }

        // Then drop earlier days' snapshots, and nothing else that is in there.
        let files = (try? fm.contentsOfDirectory(at: savesDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != todayName
            && file.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Derived values

    func remainingCount(in page: Page) -> Int {
        todos.filter { page.contains($0) && !$0.isDone }.count
    }

    func totalCount(in page: Page) -> Int {
        todos.filter { page.contains($0) }.count
    }

    func doneCount(in page: Page) -> Int {
        todos.filter { page.contains($0) && $0.isDone }.count
    }

    func starredCount(in page: Page) -> Int {
        todos.filter { page.contains($0) && $0.isStarred }.count
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

    /// Every task with a due date, from both horizons, soonest first.
    func dueItems(filter: Filter) -> [Todo] {
        todos
            .filter { $0.dueDate != nil && filter.matches($0) }
            .sorted(by: Self.byDue)
    }

    /// Everything on screen for one page, top to bottom — the order the arrow
    /// keys walk through.
    func visibleItems(in page: Page, filter: Filter) -> [Todo] {
        switch page {
        case .shortTerm: return Bucket.allCases.flatMap { items(in: $0, filter: filter) }
        case .longTerm:  return longTermItems(filter: filter)
        case .due:       return dueItems(filter: filter)
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

    /// Soonest due first, with finished tasks moved to the bottom like
    /// everywhere else. Tasks due at the same moment fall back to `inOrder`.
    static func byDue(_ a: Todo, _ b: Todo) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        let due = (a.dueDate ?? .distantFuture, b.dueDate ?? .distantFuture)
        if due.0 != due.1 { return due.0 < due.1 }
        return inOrder(a, b)
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

    /// Sets or clears (nil) a task's due date.
    func setDue(_ todo: Todo, to date: Date?) {
        setDue([todo], to: date)
    }

    func delete(_ todo: Todo) {
        delete([todo])
    }

    // MARK: Several tasks at once

    // Each of these is one change, so a single ⌘Z puts back the whole batch.

    /// Sets or clears (nil) the due date on every task given.
    func setDue(_ group: [Todo], to date: Date?) {
        updateAll(group, named(date == nil ? "Remove Due Date" : "Set Due Date", group)) {
            $0.dueDate = date
        }
    }

    /// Every unfinished task in one section, for "set a due date on all of them".
    func openItems(in bucket: Bucket) -> [Todo] {
        todos.filter { $0.place == .shortTerm(bucket) && !$0.isDone }
    }

    func setDone(_ group: [Todo], _ done: Bool) {
        updateAll(group, named(done ? "Mark as Done" : "Mark as Not Done", group)) { $0.isDone = done }
    }

    func setStarred(_ group: [Todo], _ starred: Bool) {
        unstarUndo = nil
        updateAll(group, named(starred ? "Star" : "Remove Star", group)) { $0.isStarred = starred }
    }

    /// Sets how far along the tasks are, in quarters (0 clears it). Saying a
    /// task is part done also means it is not finished, so it is unticked.
    func setProgress(_ group: [Todo], to quarters: Int) {
        let quarters = min(max(quarters, Todo.quarters.lowerBound), Todo.quarters.upperBound)
        updateAll(group, named(quarters == 0 ? "Clear Progress" : "Set Progress", group)) {
            $0.progress = quarters
            $0.isDone = false
        }
    }

    func delete(_ group: [Todo]) {
        let ids = Set(group.map(\.id))
        change(group.count > 1 ? "Delete \(group.count) Tasks" : "Delete Task") { list in
            list.removeAll { ids.contains($0.id) }
        }
    }

    /// "Set Due Date", or "Set Due Date for 5 Tasks" when it covers several.
    private func named(_ action: String, _ group: [Todo]) -> String {
        group.count > 1 ? "\(action) for \(group.count) Tasks" : action
    }

    /// Takes the star off every task on one page, remembering which ones so
    /// `restoreStars` can undo it. Scoped like clearCompleted: tasks that are
    /// not on screen are never touched.
    func unstarAll(in page: Page) {
        let ids = Set(todos.filter { page.contains($0) && $0.isStarred }.map(\.id))
        guard !ids.isEmpty else { return }
        change("Unstar All") { list in
            for i in list.indices where ids.contains(list[i].id) {
                list[i].isStarred = false
            }
        }
        unstarUndo = UnstarUndo(page: page, ids: ids)
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

    /// Scoped to the page on screen, so clearing one view never touches the other.
    func clearCompleted(in page: Page) {
        change("Clear Completed") { list in list.removeAll { page.contains($0) && $0.isDone } }
    }

    /// Closing a save failure brings back whatever it covered.
    func dismissProblem() {
        problem = problemIsSaveFailure ? coveredProblem : nil
        problemIsSaveFailure = false
        coveredProblem = nil
    }

    private func update(_ todo: Todo, _ actionName: String, _ edit: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        change(actionName) { edit(&$0[i]) }
    }

    private func updateAll(_ group: [Todo], _ actionName: String, _ edit: (inout Todo) -> Void) {
        let ids = Set(group.map(\.id))
        change(actionName) { list in
            for i in list.indices where ids.contains(list[i].id) { edit(&list[i]) }
        }
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
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            // No file yet is the normal first launch, not an error.
            return
        } catch {
            // Most often macOS denied access to Documents. That also makes the
            // file look missing to an existence check, which is why this reads
            // it rather than asking first. The tasks are still there, so saving
            // an empty list over them is the one thing not to do.
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

    /// The file format: pretty-printed JSON with ISO 8601 dates, shared by the
    /// task file and the daily snapshots.
    private static func encode(_ todos: [Todo]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(todos)
    }

    private func save() {
        guard !writesBlocked else { return }
        do {
            let data = try Self.encode(todos)
            try data.write(to: fileURL, options: .atomic)
            if problemIsSaveFailure { dismissProblem() }
        } catch {
            if !problemIsSaveFailure { coveredProblem = problem }
            problem = "Couldn't save your tasks (\(error.localizedDescription)). "
                + "Recent changes are only in memory and will be lost when the app quits."
            problemIsSaveFailure = true
        }
    }
}
