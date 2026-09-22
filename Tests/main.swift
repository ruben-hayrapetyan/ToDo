import Foundation

// A plain executable rather than XCTest, so the tests run with only the
// Command Line Tools — the same constraint as the app itself. Run ./test.sh.

var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String,
           file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        failures += 1
        print("  ✘ \(message)  (\(file):\(line))")
    }
}

func test(_ name: String, _ body: (URL) throws -> Void) {
    print("• \(name)")
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("todo-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }
    do { try body(dir) } catch { failures += 1; print("  ✘ threw \(error)") }
}

func write(_ text: String, to url: URL) throws {
    try text.data(using: .utf8)!.write(to: url)
}

func contents(of url: URL) -> String? {
    (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
}

func files(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

// MARK: - Loading

test("missing file is a clean first launch") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    check(store.todos.isEmpty, "starts empty")
    check(store.problem == nil, "no problem reported")
}

test("unreadable JSON is moved aside, never overwritten") { dir in
    let url = dir.appendingPathComponent("todos.json")
    try write("{ this is not json", to: url)
    let store = TodoStore(storeURL: url)
    check(store.todos.isEmpty, "starts empty")
    check(store.problem != nil, "reports the problem")
    let aside = files(in: dir).filter { $0.hasPrefix("todos.unreadable-") }
    check(aside.count == 1, "original set aside (found \(files(in: dir)))")
    if let name = aside.first {
        check(contents(of: dir.appendingPathComponent(name)) == "{ this is not json",
              "set-aside file keeps the original bytes")
    }
    store.add("New task", to: .readings)
    check(store.todos.count == 1, "can keep working")
    check(contents(of: url)?.contains("New task") == true, "new file written")
}

test("one bad task doesn't lose the others, and the original is backed up") { dir in
    let url = dir.appendingPathComponent("todos.json")
    try write("""
    [
      {"id":"D03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Good","bucket":"readings"},
      {"id":"not-a-uuid","title":"Bad"},
      {"id":"E03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Also good","bucket":"email"}
    ]
    """, to: url)
    let store = TodoStore(storeURL: url)
    check(store.todos.map(\.title) == ["Good"], "keeps the readable task (got \(store.todos.map(\.title)))")
    check(store.problem?.contains("2 tasks") == true, "says how many were skipped")
    let backups = files(in: dir).filter { $0.hasPrefix("todos.unreadable-") }
    check(backups.count == 1, "backup made")
    check(contents(of: url)?.contains("not-a-uuid") == true, "original untouched until the next change")
}

test("a file that can't be opened blocks all writes") { dir in
    let url = dir.appendingPathComponent("todos.json")
    try write("[]", to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
    let store = TodoStore(storeURL: url)
    check(store.writesBlocked, "writes blocked")
    check(store.problem != nil, "reports the problem")
    store.add("Would clobber", to: .other)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    check(contents(of: url) == "[]", "file left untouched")
}

test("a failed save is reported, and cleared by the next good one") { dir in
    let folder = dir.appendingPathComponent("locked", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("todos.json")
    let store = TodoStore(storeURL: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    store.add("Lost?", to: .other)
    check(store.problem?.contains("Couldn't save") == true, "save failure reported")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    store.add("Saved", to: .other)
    check(store.problem == nil, "cleared after a successful save")
    check(contents(of: url)?.contains("Lost?") == true, "earlier change reaches disk too")
}

// MARK: - Format

test("old files load with defaults; long-term tasks drop the placeholder bucket") { dir in
    let url = dir.appendingPathComponent("todos.json")
    try write("""
    [
      {"id":"D03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Ancient"},
      {"id":"E03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Someday","horizon":"longTerm","bucket":"other"}
    ]
    """, to: url)
    let store = TodoStore(storeURL: url)
    check(store.todos.first?.place == .shortTerm(.assignments), "no horizon or bucket → assignments")
    check(store.todos.first?.isStarred == false, "no star → false")
    check(store.todos.last?.place == .longTerm, "long term")
    store.toggle(store.todos.last!)
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    check(saved[0]["bucket"] as? String == "assignments", "short-term bucket written")
    check(saved[1]["bucket"] == nil, "long-term bucket omitted")
    check(saved[1]["horizon"] as? String == "longTerm", "horizon written")
}

// MARK: - Order

test("natural sort, done last, ties stable") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    for title in ["chapter 11", "Chapter 3", "same", "same", "Alpha"] { store.add(title, to: .readings) }
    store.toggle(store.todos.first { $0.title == "Alpha" }!)
    let titles = store.items(in: .readings, filter: .all).map(\.title)
    check(titles == ["Chapter 3", "chapter 11", "same", "same", "Alpha"], "order (got \(titles))")
    let sames = store.todos.filter { $0.title == "same" }
    let ids = store.items(in: .readings, filter: .all).filter { $0.title == "same" }.map(\.id)
    check(ids == sames.map(\.id), "equal titles keep insertion order")
}

test("visible items walk sections top to bottom") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    store.add("mail", to: .emails)
    store.add("read", to: .readings)
    store.addLongTerm("later")
    check(store.visibleItems(in: .shortTerm, filter: .all).map(\.title) == ["read", "mail"], "short term")
    check(store.visibleItems(in: .longTerm, filter: .all).map(\.title) == ["later"], "long term")
}

// MARK: - Undo

test("undo and redo across edits") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    let undo = UndoManager()
    undo.groupsByEvent = false
    store.undoManager = undo

    func step(_ body: () -> Void) { undo.beginUndoGrouping(); body(); undo.endUndoGrouping() }

    step { store.add("Keep me", to: .readings) }
    let task = store.todos[0]
    step { store.delete(task) }
    check(store.todos.isEmpty, "deleted")
    check(undo.undoActionName == "Delete Task", "menu names the action")
    undo.undo()
    check(store.todos.map(\.id) == [task.id], "delete undone")
    undo.redo()
    check(store.todos.isEmpty, "delete redone")
    undo.undo()
    step { store.rename(store.todos[0], to: "Renamed") }
    undo.undo()
    check(store.todos[0].title == "Keep me", "rename undone")
    step { store.rename(store.todos[0], to: "   ") }
    check(store.todos.isEmpty, "empty rename deletes")
    undo.undo()
    check(store.todos.count == 1, "and that is undoable too")
}

test("unstar all, restore, and undo stay consistent") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    store.add("a", to: .readings); store.add("b", to: .readings); store.addLongTerm("c")
    for t in store.todos { store.toggleStar(t) }
    store.unstarAll(in: .shortTerm)
    check(store.starredCount(in: .shortTerm) == 0, "short term unstarred")
    check(store.starredCount(in: .longTerm) == 1, "long term untouched")
    store.restoreStars()
    check(store.starredCount(in: .shortTerm) == 2, "restored")
    check(store.unstarUndo == nil, "restore retires itself")
}

// MARK: - Migration

test("migration moves once and never overwrites") { dir in
    let legacy = dir.appendingPathComponent("old/todos.json")
    let fresh = dir.appendingPathComponent("new/todos.json")
    try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try write("[\"old\"]", to: legacy)
    check(TodoStore.migrate(from: legacy, to: fresh), "moved")
    check(contents(of: fresh) == "[\"old\"]", "content moved")
    check(!FileManager.default.fileExists(atPath: legacy.deletingLastPathComponent().path), "empty old folder removed")
    try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try write("[\"stale\"]", to: legacy)
    check(!TodoStore.migrate(from: legacy, to: fresh), "refuses when destination exists")
    check(contents(of: fresh) == "[\"old\"]", "destination untouched")
}

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
