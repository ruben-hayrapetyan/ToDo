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

test("a failed save takes over the banner, and gives it back once saving works") { dir in
    let folder = dir.appendingPathComponent("locked", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("todos.json")
    try write("""
    [
      {"id":"D03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Good","bucket":"readings"},
      {"id":"not-a-uuid","title":"Bad"}
    ]
    """, to: url)
    let store = TodoStore(storeURL: url)
    let loadProblem = store.problem
    check(loadProblem?.contains("1 task") == true, "load problem shown")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    store.add("Lost?", to: .other)
    check(store.problem?.contains("Couldn't save") == true, "save failure shown over it")
    store.dismissProblem()
    check(store.problem == loadProblem, "closing it brings the load problem back")
    store.add("Still lost?", to: .other)
    check(store.problem?.contains("Couldn't save") == true, "a later failure shows again")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    store.add("Saved", to: .other)
    check(store.problem == loadProblem, "a good save brings it back too")
    check(contents(of: url)?.contains("Lost?") == true, "and the earlier changes reach disk")
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

test("due page lists dated tasks from both horizons, soonest first") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    let now = Date()
    store.add("undated", to: .readings)
    store.add("friday", to: .emails)
    store.addLongTerm("next month")
    store.add("overdue", to: .assignments)
    store.add("finished early", to: .other)
    func task(_ title: String) -> Todo { store.todos.first { $0.title == title }! }
    store.setDue(task("friday"), to: now.addingTimeInterval(3 * 86_400))
    store.setDue(task("next month"), to: now.addingTimeInterval(30 * 86_400))
    store.setDue(task("overdue"), to: now.addingTimeInterval(-3600))
    store.setDue(task("finished early"), to: now.addingTimeInterval(-7200))
    store.toggle(task("finished early"))

    let titles = store.visibleItems(in: .due, filter: .all).map(\.title)
    check(titles == ["overdue", "friday", "next month", "finished early"], "soonest first, done last (got \(titles))")
    check(store.visibleItems(in: .due, filter: .active).map(\.title) == ["overdue", "friday", "next month"], "filter applies")
    check(store.totalCount(in: .due) == 4 && store.doneCount(in: .due) == 1, "counts cover dated tasks only")

    store.clearCompleted(in: .due)
    check(store.todos.count == 4 && store.todos.allSatisfy { !$0.isDone }, "clear completed on the due page")
    store.setDue(task("undated"), to: now.addingTimeInterval(60))
    let after = store.dueItems(filter: .all).map(\.title)
    check(after == ["overdue", "undated", "friday", "next month"], "dating a task puts it in order (got \(after))")
}

// MARK: - Undo

test("undo keeps the last \(TodoStore.undoLevels) changes") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    let undo = UndoManager()
    undo.groupsByEvent = false
    store.undoManager = undo
    for i in 0...TodoStore.undoLevels {
        undo.beginUndoGrouping()
        store.add("Task \(i)", to: .other)
        undo.endUndoGrouping()
    }
    var undone = 0
    while undo.canUndo { undo.undo(); undone += 1 }
    check(undone == TodoStore.undoLevels && store.todos.map(\.title) == ["Task 0"],
          "the oldest change drops off (undid \(undone))")
}

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

// MARK: - Due dates

test("due date round-trips, persists, and undoes") { dir in
    let url = dir.appendingPathComponent("todos.json")
    let store = TodoStore(storeURL: url)
    let undo = UndoManager()
    undo.groupsByEvent = false
    store.undoManager = undo
    func step(_ body: () -> Void) { undo.beginUndoGrouping(); body(); undo.endUndoGrouping() }
    step { store.add("a", to: .readings) }
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    step { store.setDue(store.todos[0], to: due) }
    check(store.todos[0].dueDate == due, "due date set")
    check(TodoStore(storeURL: url).todos.first?.dueDate == due, "due date reloads")
    undo.undo()
    check(store.todos[0].dueDate == nil, "undo clears it")
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    check(saved[0]["dueDate"] == nil, "no key when unset")
}

test("due state: date, countdown, then overdue counting up from 0") { _ in
    let due = Date(timeIntervalSince1970: 1_000_000)
    func state(_ offset: TimeInterval) -> DueState { DueState(due: due, now: due.addingTimeInterval(offset)) }
    check(state(-86_400) == .later(due), "a full day out shows the date")
    check(state(-86_399) == .countdown(86_399), "just under a day counts down")
    check(state(0) == .overdue(0), "at the deadline it is overdue at 0")
    check(state(5) == .overdue(5), "then counts up")
    check(DueState.countdown(3661).text == "1:01:01", "countdown text")
    check(DueState.countdown(0.2).text == "0:00:01", "countdown rounds up")
    func late(_ s: TimeInterval) -> String { DueState.overdue(s).text }
    check(late(0) == "+0s", "overdue starts at zero")
    check(late(59.9) == "+59s", "overdue rounds down")
    check(late(61) == "+1m 1s", "minutes and seconds")
    check(late(3600) == "+1h 0m 0s", "zeros inside the top three are kept")
    check(late(3661) == "+1h 1m 1s", "hours, minutes, seconds")
    check(late(90_061) == "+1d 1h 1m", "seconds drop off once days show")
    check(late(702_121) == "+1w 1d 3h", "weeks, days, hours")
    check(late(604_800) == "+1w 0d 0h", "exactly a week")
    check(late(3 * 604_800 + 4 * 86_400 + 5 * 3600 + 59) == "+3w 4d 5h", "later weeks")
}

test("due labels wake only when their text changes") { _ in
    let due = Date(timeIntervalSince1970: 1_000_000)
    // Seconds from the deadline to the next redraw, starting `offset` from it.
    func next(_ offset: TimeInterval) -> TimeInterval {
        DueState.nextChange(due: due, after: due.addingTimeInterval(offset))
            .timeIntervalSince(due)
    }
    check(next(-30 * 86_400) == -86_399, "a date sleeps until the countdown")
    check(next(-86_400) == -86_399, "and wakes as it starts")
    check(next(-3661) == -3660, "the countdown ticks each second")
    check(next(-3660.5) == -3660, "on whole seconds from the deadline")
    check(next(-0.2) == 0, "the last second flips to overdue")
    check(next(0) == 1, "overdue counts seconds")
    check(next(86_399.5) == 86_400, "until a day has passed")
    check(next(86_400) == 86_460, "then minutes")
    check(next(604_799) == 604_800, "until a week")
    check(next(604_800) == 608_400, "then hours")

    // Walking two days out to nine days late: the text changes at every step
    // and holds still halfway to the next one.
    var now = due.addingTimeInterval(-2 * 86_400)
    var steps = 0
    let failuresBefore = failures
    while now < due.addingTimeInterval(9 * 86_400) && failures == failuresBefore {
        let after = DueState.nextChange(due: due, after: now)
        let text = DueState(due: due, now: now).text
        check(after > now, "the schedule moves forward")
        check(DueState(due: due, now: after).text != text, "text changes at \(after)")
        let mid = now.addingTimeInterval(after.timeIntervalSince(now) / 2)
        check(DueState(due: due, now: mid).text == text, "and not before \(after)")
        now = after
        steps += 1
    }
    // The date, each countdown second, each second of the first late day,
    // each minute to a week, each hour after.
    check(steps == 1 + 86_399 + 86_400 + 8640 + 48, "one step per change, got \(steps)")
}

test("typed due dates") { _ in
    let cal = Calendar.current
    let now = Date()
    func parts(_ s: String) -> (date: Date, c: DateComponents)? {
        DueParser.parse(s, now: now, calendar: cal).map {
            ($0, cal.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: $0)) }
    }

    // Worded dates are resolved by the system against the real clock, so these
    // are checked relative to it rather than against a fixed date.
    if let r = parts("3pm") {
        check(r.c.hour == 15 && r.c.minute == 0, "3pm is 15:00")
        check(r.date > now && r.date <= now.addingTimeInterval(86_400), "3pm is the next 3pm")
    } else { check(false, "3pm parses") }

    let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
    if let r = parts("tomorrow 5pm") {
        check(cal.isDate(r.date, inSameDayAs: tomorrow) && r.c.hour == 17, "tomorrow 5pm")
    } else { check(false, "tomorrow 5pm parses") }

    if let r = parts("fri 9:30am") {
        check(r.c.weekday == 6 && r.c.hour == 9 && r.c.minute == 30, "friday with a time")
    } else { check(false, "fri 9:30am parses") }

    if let r = parts("friday") {
        check(r.c.weekday == 6 && r.c.hour == 23 && r.c.minute == 59, "day alone → end of that day")
    } else { check(false, "friday parses") }

    // Only a bare time rolls over to tomorrow; a typed-out date means that day.
    let monthDay = DateFormatter()
    monthDay.locale = Locale(identifier: "en_US_POSIX")
    monthDay.dateFormat = "MMM d"
    if let r = parts(monthDay.string(from: now).lowercased() + " 12:00am") {
        check(cal.isDate(r.date, inSameDayAs: now), "today's date with a past time stays today")
    } else { check(false, "a typed-out date with a time parses") }

    if let r = parts("tomorrow morning") {
        check(cal.isDate(r.date, inSameDayAs: tomorrow) && r.c.hour! < 12, "a time of day is kept")
    } else { check(false, "tomorrow morning parses") }

    // A day that has already gone means the next one, unless the text says so.
    let lastWeek = cal.date(byAdding: .day, value: -7, to: now)!
    let weekdayAndDay = DateFormatter()
    weekdayAndDay.locale = Locale(identifier: "en_US_POSIX")
    weekdayAndDay.dateFormat = "EEE d"
    for text in [monthDay, weekdayAndDay].map({ $0.string(from: lastWeek).lowercased() }) {
        if let r = parts(text) {
            check(r.date > now, "'\(text)' is not in the past (got \(r.date))")
        } else { check(false, "'\(text)' parses") }
    }
    if let r = parts(monthDay.string(from: lastWeek).lowercased()) {
        let gone = cal.dateComponents([.month, .day], from: lastWeek)
        check(r.c.month == gone.month && r.c.day == gone.day
              && r.date < cal.date(byAdding: .year, value: 1, to: now)!, "a gone date is the next one")
    }
    check(parts("10/14/2025")?.c.year == 2025, "a typed year is kept")
    if let r = parts("yesterday") {
        check(cal.isDate(r.date, inSameDayAs: cal.date(byAdding: .day, value: -1, to: now)!),
              "yesterday is taken at its word")
    } else { check(false, "yesterday parses") }

    // These are computed from the `now` passed in, so a fixed one works.
    var nyCal = Calendar(identifier: .gregorian)
    nyCal.timeZone = TimeZone(identifier: "America/New_York")!
    let fixed = nyCal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 11))!
    func fixedParts(_ s: String) -> DateComponents? {
        DueParser.parse(s, now: fixed, calendar: nyCal).map {
            nyCal.dateComponents([.month, .day, .hour, .minute], from: $0) }
    }
    func dc(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> DateComponents {
        DateComponents(month: m, day: d, hour: h, minute: min)
    }
    check(fixedParts("eod") == dc(9, 23, 23, 59), "eod")
    check(fixedParts("in 2 hours") == dc(9, 23, 13, 0), "in 2 hours")
    check(fixedParts("90m") == dc(9, 23, 12, 30), "90m")
    check(fixedParts("1d 4h") == dc(9, 24, 15, 0), "1d 4h")
    check(fixedParts("noon") == dc(9, 23, 12, 0) || fixedParts("noon") == dc(9, 24, 12, 0), "noon")
    check(fixedParts("banana") == nil, "gibberish is nil")
    check(fixedParts("   ") == nil, "blank is nil")
}

// MARK: - Keeping existing data

test("a file from before progress keeps every field through a save") { dir in
    let url = dir.appendingPathComponent("todos.json")
    try write("""
    [
      {"id":"D03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Math HW 2","horizon":"shortTerm",
       "bucket":"assignments","isDone":false,"isStarred":true,
       "createdAt":"2026-09-01T03:53:02Z","dueDate":"2026-09-05T23:59:00Z"},
      {"id":"E03C6939-CC09-44B1-8B16-B456A167BDA1","title":"Someday","horizon":"longTerm",
       "isDone":true,"isStarred":false,"createdAt":"2026-09-02T10:00:00Z"}
    ]
    """, to: url)
    let before = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    let store = TodoStore(storeURL: url)
    check(store.problem == nil, "loads cleanly")
    // Force a save by changing something unrelated, then changing it back.
    store.add("temp", to: .other)
    store.delete(store.todos.first { $0.title == "temp" }!)
    let after = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    check(after.count == before.count, "same number of tasks")
    for (old, new) in zip(before, after) {
        check(NSDictionary(dictionary: old).isEqual(to: new),
              "task saved back exactly (was \(old), now \(new))")
    }
}

// MARK: - Progress

test("progress persists, is left out when empty, and survives a tick") { dir in
    let url = dir.appendingPathComponent("todos.json")
    let store = TodoStore(storeURL: url)
    store.add("Hamlet", to: .readings)
    store.setProgress([store.todos[0]], to: 2)
    check(store.todos[0].progress == 2, "set to half")
    check(TodoStore(storeURL: url).todos[0].progress == 2, "reloads")
    store.setDone([store.todos[0]], true)
    check(store.todos[0].isDone && store.todos[0].progress == 2, "ticking keeps the quarters")
    store.setDone([store.todos[0]], false)
    check(store.todos[0].progress == 2, "unticking puts them back")
    store.setDone([store.todos[0]], true)
    store.setProgress([store.todos[0]], to: 1)
    check(!store.todos[0].isDone, "setting progress unticks")
    store.setProgress([store.todos[0]], to: 9)
    check(store.todos[0].progress == 3, "clamped to ¾")
    store.setProgress([store.todos[0]], to: 0)
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    check(saved[0]["progress"] == nil, "no key when empty")
}

test("out-of-range progress in the file is clamped, not rejected") { dir in
    let url = dir.appendingPathComponent("todos.json")
    try write("""
    [{"id":"D03C6939-CC09-44B1-8B16-B456A167BDA1","title":"a","progress":7},
     {"id":"E03C6939-CC09-44B1-8B16-B456A167BDA1","title":"b","progress":-2}]
    """, to: url)
    let store = TodoStore(storeURL: url)
    check(store.todos.map(\.progress) == [3, 0], "clamped (got \(store.todos.map(\.progress)))")
}

// MARK: - Several at once

test("one due date on many tasks is one undo step") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    let undo = UndoManager()
    undo.groupsByEvent = false
    store.undoManager = undo
    func step(_ body: () -> Void) { undo.beginUndoGrouping(); body(); undo.endUndoGrouping() }
    step { for t in ["a", "b", "c"] { store.add(t, to: .assignments) } }
    step { store.add("r", to: .readings) }
    let early = Date(timeIntervalSince1970: 1_700_000_000)
    step { store.setDue([store.todos[0]], to: early) }
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    step { store.setDue(store.openItems(in: .assignments), to: due) }
    check(store.todos.filter { $0.bucket == .assignments }.allSatisfy { $0.dueDate == due }, "all set")
    check(store.todos.first { $0.bucket == .readings }?.dueDate == nil, "other sections untouched")
    check(undo.undoActionName == "Set Due Date for 3 Tasks", "menu names the batch (got \(undo.undoActionName))")
    undo.undo()
    check(store.todos.map(\.dueDate) == [early, nil, nil, nil], "one undo puts every date back")
}

test("open items leave out finished tasks") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    store.add("a", to: .assignments); store.add("b", to: .assignments)
    store.toggle(store.todos[1])
    check(store.openItems(in: .assignments).map(\.title) == ["a"], "done one skipped")
}

test("batch done, star, and delete") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    for t in ["a", "b", "c"] { store.add(t, to: .emails) }
    let two = Array(store.todos.prefix(2))
    store.setDone(two, true)
    store.setStarred(two, true)
    check(store.todos.map(\.isDone) == [true, true, false], "two ticked")
    check(store.todos.map(\.isStarred) == [true, true, false], "two starred")
    store.delete(two)
    check(store.todos.map(\.title) == ["c"], "two deleted")
}

// MARK: - Selection

test("selection: click, ⌘-click, ⇧-click and ⇧-arrows") { _ in
    let ids = (0..<5).map { _ in UUID() }
    var sel = Selection()
    sel.move(by: 1, in: ids, extending: false)
    check(sel.ids == [ids[0]] && sel.cursor == ids[0], "↓ from nothing lands on the first")
    sel.move(by: 1, in: ids, extending: true)
    sel.move(by: 1, in: ids, extending: true)
    check(sel.ids == Set(ids[0...2]) && sel.cursor == ids[2], "⇧↓ grows the run")
    sel.move(by: -1, in: ids, extending: true)
    check(sel.ids == Set(ids[0...1]), "⇧↑ shrinks it back toward the anchor")
    sel.select(ids[3])
    sel.extend(to: ids[1], in: ids)
    check(sel.ids == Set(ids[1...3]), "⇧-click upward runs from the anchor")
    sel.toggle(ids[4])
    check(sel.ids == Set(ids[1...4]), "⌘-click adds")
    sel.toggle(ids[2])
    check(sel.ids == [ids[1], ids[3], ids[4]], "⌘-click drops")
    sel.move(by: 1, in: ids, extending: false)
    check(sel.ids == [ids[3]], "plain arrow collapses to one")
    sel.toggle(ids[3])
    check(sel.isEmpty && sel.cursor == nil, "dropping the last one clears everything")
    sel.extend(to: ids[2], in: ids)
    check(sel.ids == [ids[2]], "⇧-click with no anchor is a plain click")
    sel.selectAll(ids)
    check(sel.count == 5, "select all")
    sel.move(by: -1, in: [], extending: false)
    check(sel.count == 5, "an empty list leaves it alone")
}

test("selection keeps on-screen order, even across sections") { dir in
    let store = TodoStore(storeURL: dir.appendingPathComponent("todos.json"))
    store.add("r", to: .readings); store.add("m", to: .emails); store.add("a", to: .assignments)
    let visible = store.visibleItems(in: .shortTerm, filter: .all)
    var sel = Selection()
    sel.select(visible[0].id)
    sel.extend(to: visible[2].id, in: visible.map(\.id))
    check(sel.chosen(from: visible).map(\.title) == ["r", "a", "m"], "reading, assignment, email")
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
