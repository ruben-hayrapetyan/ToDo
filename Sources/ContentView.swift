import SwiftUI

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var window: WindowState

    /// Stored rather than plain @State so the app reopens on whichever tab you
    /// were last using — otherwise long-term tasks look missing after a restart.
    @AppStorage("selectedHorizon") private var horizonRaw = Horizon.shortTerm.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow

    private var horizon: Horizon {
        get { Horizon(rawValue: horizonRaw) ?? .shortTerm }
        nonmutating set { horizonRaw = newValue.rawValue }
    }

    private var accent: Color { Paper.accent(for: horizon) }
    private var filter: Filter { window.filter }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            if let problem = store.problem {
                ProblemBanner(text: problem, dismiss: store.dismissProblem)
                Hairline()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    TaskList(horizon: horizon, filter: filter)
                }
                // Keep the arrow-key selection on screen.
                .onChange(of: window.selection.cursor) { id in
                    if let id = id { proxy.scrollTo(id) }
                }
            }

            Hairline()
            footer
        }
        .background(Paper.sheet.ignoresSafeArea())
        .frame(minWidth: 420, minHeight: 460)
        .onAppear {
            store.undoManager = undoManager
            let open = openWindow
            window.reopenWindow = { open(id: TodoListApp.windowID) }
        }
        .onChange(of: undoManager) { store.undoManager = $0 }
        // A shortcut aimed at the other view switches to it first; the field
        // itself claims focus once it appears.
        .onChange(of: window.target) { target in
            switch target {
            case .bucket:   horizon = .shortTerm
            case .longTerm: horizon = .longTerm
            case nil:       break
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Todo List")
                    .font(Face.wordmark)
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text(standing)
                    .font(Face.code(10.5))
                    .foregroundStyle(Paper.muted)
            }

            horizonTabs
            filterRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 11)
        .background(Paper.band)
    }

    private var standing: String {
        if store.totalCount(in: horizon) == 0 { return "nothing here" }
        let open = store.remainingCount(in: horizon)
        return open == 0 ? "all clear" : "\(open) open"
    }

    /// The two inks. Switching them is the app's one mode change, so it gets the
    /// only underline in the interface.
    private var horizonTabs: some View {
        HStack(spacing: 20) {
            ForEach(Horizon.allCases) { candidate in
                Button {
                    withAnimation(motion(.easeInOut(duration: 0.18))) { horizon = candidate }
                } label: {
                    Text(candidate.title.lowercased())
                        .font(Face.code(11))
                        .tracking(1.5)
                        .foregroundStyle(candidate == horizon ? Paper.ink : Paper.muted)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(candidate == horizon
                                      ? Paper.accent(for: candidate) : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .help("Show \(candidate.title.lowercased()) tasks")
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Paper.rule).frame(height: 1)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Filter.allCases.enumerated()), id: \.element) { index, candidate in
                if index > 0 {
                    Text("·")
                        .font(Face.code(9.5))
                        .foregroundStyle(Paper.faint)
                        .padding(.horizontal, 7)
                }
                Button {
                    withAnimation(motion(.easeInOut(duration: 0.15))) { window.filter = candidate }
                } label: {
                    Text(candidate.rawValue.lowercased())
                        .font(Face.code(9.5, weight: candidate == filter ? .bold : .medium))
                        .tracking(0.9)
                        .foregroundStyle(candidate == filter ? Paper.ink : Paper.faint)
                }
                .buttonStyle(.plain)
                .help("Show \(candidate.rawValue.lowercased()) tasks")
            }
            Spacer()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Text(footerCount)
                .font(Face.code(10, weight: .medium))
                .foregroundStyle(Paper.muted)
                .layoutPriority(1)

            Spacer(minLength: 10)

            starToggle

            Text("·")
                .font(Face.code(10))
                .foregroundStyle(Paper.faint)
                .padding(.horizontal, 7)

            clearCompletedButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Paper.band)
    }

    /// The task tally, or with several selected, how many and what to press.
    private var footerCount: String {
        let selected = window.selection.chosen(from: store.visibleItems(in: horizon, filter: filter)).count
        if selected > 1 { return "\(selected) selected · d sets a due date" }
        return "\(store.totalCount(in: horizon)) tasks · \(store.doneCount(in: horizon)) done"
    }

    /// One control with two faces: it takes the star off everything in this
    /// view, then offers to put back exactly what it removed.
    private var starToggle: some View {
        let restoring = store.unstarUndo?.horizon == horizon
        let count = restoring
            ? (store.unstarUndo?.ids.count ?? 0)
            : store.starredCount(in: horizon)
        let enabled = count > 0

        return Button {
            withAnimation(motion(.easeInOut(duration: 0.2))) {
                if restoring { store.restoreStars() } else { store.unstarAll(in: horizon) }
            }
        } label: {
            Text(restoring ? "Restore stars" : "Unstar all")
                .font(Face.code(10, weight: .semibold))
                .foregroundStyle(!enabled ? Paper.faint : (restoring ? Paper.mark : accent))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(restoring
              ? "Put back the \(count) star\(count == 1 ? "" : "s") just removed"
              : "Take the star off every \(horizon.title.lowercased()) task")
    }

    private var clearCompletedButton: some View {
        Button {
            withAnimation(motion(.easeInOut(duration: 0.2))) {
                store.clearCompleted(in: horizon)
            }
        } label: {
            Text("Clear completed")
                .font(Face.code(10, weight: .semibold))
                .foregroundStyle(store.doneCount(in: horizon) == 0 ? Paper.faint : accent)
        }
        .buttonStyle(.plain)
        .disabled(store.doneCount(in: horizon) == 0)
        .help("Removes finished \(horizon.title.lowercased()) tasks only")
    }

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - The page

/// Everything between the header and the footer. Split out from ContentView so
/// it can be rendered on its own, without a scroll view, for design review.
struct TaskList: View {
    let horizon: Horizon
    let filter: Filter

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if horizon == .shortTerm {
                ForEach(Array(Bucket.allCases.enumerated()), id: \.element) { index, bucket in
                    BucketSection(bucket: bucket,
                                  shortcutNumber: index + 1,
                                  filter: filter)
                }
            } else {
                LongTermList(filter: filter)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
}

// MARK: - Shared pieces

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Paper.rule).frame(height: 1)
    }
}

/// A section's header: its four-letter code, a rule, and what is left to do.
/// The rule is not decoration — it carries the eye from the code to the count.
struct SectionRule: View {
    let code: String
    let count: Int
    /// Offered as a calendar under the pointer: one due date for every open
    /// task in the section.
    var setDue: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(code)
                .font(Face.code(10.5))
                .tracking(1.7)
                .foregroundStyle(Paper.muted)
            Rectangle().fill(Paper.rule).frame(height: 1)
            Text("\(count)")
                .font(Face.code(10.5, weight: .medium))
                .foregroundStyle(Paper.faint)
                .monospacedDigit()
            if let setDue = setDue {
                Button(action: setDue) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(Paper.faint)
                }
                .buttonStyle(.plain)
                .opacity(isHovering && count > 0 ? 1 : 0)
                .disabled(count == 0)
                .help("Set one due date on every open task here")
            }
        }
        .padding(.bottom, 7)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// The "+ …  ⌘1" line that closes every list.
struct AddLine: View {
    let prompt: String
    let hint: String
    let accent: Color
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("+")
                .font(Face.code(12))
                .foregroundStyle(isFocused.wrappedValue ? accent : Paper.faint)
                .frame(width: 24, alignment: .leading)

            TextField(prompt, text: $draft)
                .textFieldStyle(.plain)
                .font(Face.task())
                .foregroundStyle(Paper.ink)
                .focused(isFocused)
                .onSubmit(onSubmit)
                // Esc hands the keyboard back to the task list.
                .onExitCommand { isFocused.wrappedValue = false }

            if !isFocused.wrappedValue && draft.isEmpty {
                Text(hint)
                    .font(Face.code(9.5, weight: .medium))
                    .foregroundStyle(Paper.faint)
                    .padding(.leading, 8)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused.wrappedValue ? accent : Paper.rule)
                .frame(height: isFocused.wrappedValue ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.15), value: isFocused.wrappedValue)
    }
}

/// Tells the person something went wrong with the task file. Stays until
/// dismissed, or until a save succeeds again.
struct ProblemBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Paper.mark)
            Text(text)
                .font(Face.task())
                .foregroundStyle(Paper.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Paper.muted)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Paper.mark.opacity(0.12))
    }
}

struct NothingYet: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Face.code(10))
            .foregroundStyle(Paper.faint)
            .padding(.leading, 24)
            .padding(.vertical, 7)
    }
}

// MARK: - One short-term section

struct BucketSection: View {
    let bucket: Bucket
    let shortcutNumber: Int
    let filter: Filter

    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var window: WindowState
    @State private var draft = ""
    @State private var showingDuePicker = false
    @FocusState private var fieldFocused: Bool

    private var items: [Todo] { store.items(in: bucket, filter: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(code: bucket.code,
                        count: store.remainingCount(in: bucket),
                        setDue: { showingDuePicker = true })
                .contextMenu {
                    Button("Set Due Date for Every Open \(bucket.singular)…") { showingDuePicker = true }
                        .disabled(store.openItems(in: bucket).isEmpty)
                }
                .popover(isPresented: $showingDuePicker, arrowEdge: .bottom) {
                    let open = store.openItems(in: bucket)
                    DuePicker(current: DuePicker.shared(by: open),
                              subject: "every open \(bucket.singular.lowercased()) · \(open.count)",
                              set: { store.setDue(store.openItems(in: bucket), to: $0) })
                }

            if items.isEmpty {
                NothingYet(text: filter == .all
                           ? "nothing yet · ⌘\(shortcutNumber) to add"
                           : "nothing \(filter.rawValue.lowercased()) here")
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { TaskRow(todo: $0) }
                }
            }

            AddLine(prompt: bucket.prompt,
                    hint: "⌘\(shortcutNumber)",
                    accent: Paper.fresh,
                    draft: $draft,
                    isFocused: $fieldFocused,
                    onSubmit: add)
        }
        // Claimed on appear too, since switching horizon rebuilds this view
        // after the shortcut has already been set.
        .onAppear(perform: claimFocusIfWanted)
        .onChange(of: window.target) { _ in claimFocusIfWanted() }
        // Typing a new task and walking the list are separate modes.
        .onChange(of: fieldFocused) { if $0 { window.selection.clear() } }
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) { store.add(draft, to: bucket) }
        draft = ""
        fieldFocused = true          // keep going without reaching for the mouse
    }

    private func claimFocusIfWanted() {
        guard window.target == .bucket(bucket) else { return }
        fieldFocused = true
        DispatchQueue.main.async { window.target = nil }
    }
}

// MARK: - The long-term list (no sections)

struct LongTermList: View {
    let filter: Filter

    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var window: WindowState
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var items: [Todo] { store.longTermItems(filter: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                NothingYet(text: filter == .all
                           ? "nothing long term yet · ⌘L to add"
                           : "nothing \(filter.rawValue.lowercased()) here")
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { TaskRow(todo: $0) }
                }
            }

            AddLine(prompt: "Add a long-term task…",
                    hint: "⌘L",
                    accent: Paper.aged,
                    draft: $draft,
                    isFocused: $fieldFocused,
                    onSubmit: add)
        }
        .onAppear(perform: claimFocusIfWanted)
        .onChange(of: window.target) { _ in claimFocusIfWanted() }
        // Typing a new task and walking the list are separate modes.
        .onChange(of: fieldFocused) { if $0 { window.selection.clear() } }
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) { store.addLongTerm(draft) }
        draft = ""
        fieldFocused = true
    }

    private func claimFocusIfWanted() {
        guard window.target == .longTerm else { return }
        fieldFocused = true
        DispatchQueue.main.async { window.target = nil }
    }
}

// MARK: - Due date entry

/// The popover for typing a due date: "3pm", "tomorrow 5pm", "fri 9am", "in 2
/// hours". It shows how the text was read before anything is saved.
struct DuePicker: View {
    let current: Date?
    /// What the date goes on when that is more than one task: "5 tasks".
    var subject: String? = nil
    let set: (Date?) -> Void

    /// The due date the tasks already share, or nil when they differ.
    static func shared(by group: [Todo]) -> Date? {
        let dates = Set(group.map(\.dueDate))
        return dates.count == 1 ? dates.first ?? nil : nil
    }

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Date? { DueParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let subject = subject {
                Text(subject)
                    .font(Face.code(10, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(Paper.muted)
            }

            TextField("3pm, tomorrow 5pm, fri, in 2 hours…", text: $text)
                .textFieldStyle(.plain)
                .font(Face.task())
                .foregroundStyle(Paper.ink)
                .focused($focused)
                .onSubmit(commit)
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule).frame(height: 1) }

            Group {
                if let parsed = parsed {
                    Text("→ " + parsed.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated)
                        .day().hour().minute()))
                        .foregroundStyle(Paper.ink)
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Can't read that")
                        .foregroundStyle(Paper.overdue)
                } else if let current = current {
                    Text("now: " + current.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated)
                        .day().hour().minute()))
                        .foregroundStyle(Paper.muted)
                } else {
                    Text(" ")
                }
            }
            .font(Face.code(10.5, weight: .medium))

            HStack {
                if current != nil {
                    Button("Remove") { set(nil); dismiss() }
                        .foregroundStyle(Paper.overdue)
                }
                Spacer()
                Button("Set", action: commit)
                    .disabled(parsed == nil)
            }
            .font(Face.code(10.5))
        }
        .frame(width: 250)
        .padding(14)
        .onAppear { focused = true }
    }

    private func commit() {
        guard let date = parsed else { return }
        set(date)
        dismiss()
    }
}

// MARK: - Progress

/// How a quarter count reads in menus and help.
private func quarterName(_ quarters: Int) -> String {
    ["Not started", "¼ done", "½ done", "¾ done"][quarters]
}

/// The quarter-pie drawn beside a partly done task: an outline circle with
/// one wedge per quarter, filled clockwise from twelve o'clock.
struct QuarterPie: View {
    let quarters: Int

    var body: some View {
        ZStack {
            Wedge(fraction: Double(quarters) / 4)
            Circle().strokeBorder(lineWidth: 1.1)
        }
    }

    private struct Wedge: Shape {
        let fraction: Double

        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard fraction > 0 else { return path }
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            path.move(to: centre)
            // SwiftUI's y axis points down, so "counter-clockwise" here draws
            // clockwise on screen.
            path.addArc(center: centre, radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction),
                        clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - One task

struct TaskRow: View {
    let todo: Todo

    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var window: WindowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var isHovering = false
    @State private var showingDuePicker = false
    /// The tasks the open due-date popover will set, fixed when it opens.
    @State private var dueTargets: [Todo] = []
    /// True from the moment a rename starts until it is saved or cancelled —
    /// even if another row takes over `editingID` first, so the text typed here
    /// is saved rather than dropped.
    @State private var hasOpenEdit = false
    @FocusState private var editFocused: Bool

    private var isEditing: Bool { window.editingID == todo.id }
    private var isSelected: Bool { window.selection.contains(todo.id) }
    private var accent: Color { Paper.accent(for: todo.horizon) }

    /// What the row's controls act on: the whole selection when this task is
    /// part of one, otherwise just this task.
    private var targets: [Todo] { window.targets(for: todo, in: store) }

    /// The single-task wording, or the batch wording when acting on several.
    private func phrase(_ one: String, _ many: (Int) -> String) -> String {
        let count = targets.count
        return count > 1 ? many(count) : one
    }

    var body: some View {
        HStack(spacing: 0) {
            checkbox
                .frame(width: 24, alignment: .leading)

            HStack(spacing: 8) {
                if isEditing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Face.task())
                        .foregroundStyle(Paper.ink)
                        .focused($editFocused)
                        .onSubmit(commitEdit)
                        .onExitCommand(perform: cancelEdit)
                        .onChange(of: editFocused) { focused in
                            // Clicking away saves rather than dropping the edit.
                            if !focused { commitEdit() }
                        }
                } else {
                    Text(todo.title)
                        .font(Face.task(todo.isStarred ? .medium : .regular))
                        .strikethrough(todo.isDone, color: Paper.faint)
                        .foregroundStyle(todo.isDone ? Paper.faint : Paper.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2, perform: beginEdit)
                        // A single click selects the row for the arrow keys; it
                        // does not wait on the double-click that starts a
                        // rename. On the title only, so the row's buttons act
                        // on the selection instead of replacing it.
                        .simultaneousGesture(TapGesture().onEnded(select))
                }

                progressButton
                dueButton
                star
                deleteButton
            }
            .padding(.leading, 12)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 5)
        // The margin, drawn as an overlay so its weight can never push the text
        // column sideways or stretch the row.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(todo.isStarred ? Paper.mark : Paper.rule)
                .frame(width: todo.isStarred ? 3 : 1)
                .offset(x: 24)
        }
        .background(isSelected ? accent.opacity(0.12) : isHovering ? Paper.hover : Color.clear)
        .onHover { isHovering = $0 }
        .onAppear { if isEditing { openEdit() } }
        .onChange(of: window.editingID) { id in
            if id == todo.id {
                openEdit()
            } else if hasOpenEdit {
                // Another row started editing before this one lost focus.
                commitEdit()
            }
        }
        .onChange(of: window.dueRequest) { id in
            guard id == todo.id else { return }
            openDuePicker()
            window.dueRequest = nil
        }
        .contextMenu {
            Button(todo.isDone
                   ? phrase("Mark as Not Done") { "Mark \($0) as Not Done" }
                   : phrase("Mark as Done") { "Mark \($0) as Done" }) {
                store.setDone(targets, !todo.isDone)
            }
            Picker(phrase("Progress") { "Progress for \($0) Tasks" }, selection: Binding(
                get: { todo.isDone ? -1 : todo.progress },
                set: { store.setProgress(targets, to: $0) })) {
                ForEach(Todo.quarters, id: \.self) { Text(quarterName($0)).tag($0) }
            }
            Button(todo.isStarred
                   ? phrase("Remove Star") { "Remove \($0) Stars" }
                   : phrase("Star") { "Star \($0) Tasks" }) {
                store.setStarred(targets, !todo.isStarred)
            }
            Button("Edit…", action: beginEdit)
            Button(targets.count > 1
                   ? "Set Due Date for \(targets.count) Tasks…"
                   : todo.dueDate == nil ? "Set Due Date…" : "Change Due Date…") {
                openDuePicker()
            }
            if targets.contains(where: { $0.dueDate != nil }) {
                Button(phrase("Remove Due Date") { "Remove Due Dates from \($0) Tasks" }) {
                    store.setDue(targets, to: nil)
                }
            }
            Divider()
            Button(phrase("Delete") { "Delete \($0) Tasks" }, role: .destructive) {
                withAnimation(motion(.easeInOut(duration: 0.2))) { store.delete(targets) }
            }
        }
    }

    /// A ruled box, the way a checklist is drawn by hand — not the system
    /// circle. A part-done task fills with a wash of ink from the bottom, a
    /// quarter at a time; a finished one is solid with a tick.
    private var checkbox: some View {
        let box = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let partial = todo.isDone ? 0 : todo.progress
        return Button {
            withAnimation(motion(.easeInOut(duration: 0.18))) { store.setDone(targets, !todo.isDone) }
        } label: {
            ZStack {
                ZStack(alignment: .bottom) {
                    box.fill(todo.isDone ? accent : Color.clear)
                    Rectangle()
                        .fill(accent.opacity(0.45))
                        .frame(height: 14 * CGFloat(partial) / 4)
                }
                .frame(width: 14, height: 14)
                .clipShape(box)
                .overlay(box.strokeBorder(todo.isDone || partial > 0 ? accent : Paper.faint,
                                          lineWidth: 1.2))

                if todo.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Paper.band)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(todo.isDone
              ? phrase("Mark as not done") { "Mark \($0) tasks as not done" }
              : phrase("Mark as done") { "Mark \($0) tasks as done" })
    }

    /// Each click adds a quarter, and after ¾ it goes back to none. It never
    /// finishes the task: that is the checkbox's job. Shows while a task is
    /// part done, otherwise fades in under the pointer; hidden once finished.
    private var progressButton: some View {
        let next = (todo.progress + 1) % (Todo.quarters.upperBound + 1)
        return Button {
            withAnimation(motion(.easeOut(duration: 0.18))) { store.setProgress(targets, to: next) }
        } label: {
            QuarterPie(quarters: todo.progress)
                .foregroundStyle(todo.progress > 0 ? accent : Paper.faint)
                .frame(width: 10, height: 10)
                // A plain button only takes clicks on what it draws, which for
                // an empty pie is a hairline ring. Make the whole square count.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(!todo.isDone && (todo.progress > 0 || isHovering) ? 1 : 0)
        .disabled(todo.isDone)
        .help("\(quarterName(todo.progress)) · click for \(quarterName(next).lowercased())"
              + (targets.count > 1 ? " on all \(targets.count)" : "")
              + " · keys 1–3, 0 clears")
    }

    /// Stays on show once starred, alongside the marginal mark; otherwise it
    /// fades in under the pointer.
    private var star: some View {
        Button {
            withAnimation(motion(.easeOut(duration: 0.18))) { store.setStarred(targets, !todo.isStarred) }
        } label: {
            Image(systemName: todo.isStarred ? "star.fill" : "star")
                .font(.system(size: 10))
                .foregroundStyle(todo.isStarred ? Paper.mark : Paper.faint)
        }
        .buttonStyle(.plain)
        .opacity(todo.isStarred || isHovering ? 1 : 0)
        .help(todo.isStarred
              ? phrase("Remove star") { "Remove \($0) stars" }
              : phrase("Star this task") { "Star \($0) tasks" })
    }

    /// The due date, live: a date while it is a day or more away, a countdown
    /// under a day, and red counting up once it has passed. With no date set it
    /// is a calendar icon that fades in under the pointer.
    private var dueButton: some View {
        Button(action: openDuePicker) {
            if let due = todo.dueDate {
                if todo.isDone {
                    Text(DueState.later(due).text)
                        .font(Face.code(10, weight: .medium))
                        .foregroundStyle(Paper.faint)
                        .fixedSize()
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let state = DueState(due: due, now: context.date)
                        Text(state.text)
                            .font(Face.code(10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(dueColor(state))
                            .fixedSize()
                    }
                }
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(Paper.faint)
            }
        }
        .buttonStyle(.plain)
        .opacity(todo.dueDate != nil || isHovering || showingDuePicker ? 1 : 0)
        .help(targets.count > 1
              ? "Set one due date on all \(targets.count) selected tasks"
              : todo.dueDate == nil ? "Set a due date" : "Change the due date")
        .popover(isPresented: $showingDuePicker, arrowEdge: .bottom) {
            DuePicker(current: DuePicker.shared(by: dueTargets),
                      subject: dueTargets.count > 1 ? "\(dueTargets.count) tasks" : nil,
                      set: { store.setDue(dueTargets, to: $0) })
        }
    }

    private func dueColor(_ state: DueState) -> Color {
        switch state {
        case .later:     return Paper.muted
        case .countdown: return accent
        case .overdue:   return Paper.overdue
        }
    }

    private var deleteButton: some View {
        Button {
            withAnimation(motion(.easeInOut(duration: 0.2))) { store.delete(targets) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Paper.faint)
        }
        .buttonStyle(.plain)
        .opacity(isHovering && !isEditing ? 1 : 0)
        .help(phrase("Delete task") { "Delete \($0) selected tasks" })
    }

    /// Captures who the date is for when the popover opens, so it cannot drift
    /// if the selection changes underneath it.
    private func openDuePicker() {
        dueTargets = targets
        showingDuePicker = true
    }

    /// A click picks this task; ⌘-click adds it to or drops it from the
    /// selection; ⇧-click selects the run from the last click to here.
    private func select() {
        guard !isEditing else { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            window.selection.toggle(todo.id)
        } else if flags.contains(.shift) {
            let order = store.visibleItems(in: todo.horizon, filter: window.filter).map(\.id)
            window.selection.extend(to: todo.id, in: order)
        } else {
            window.selection.select(todo.id)
        }
        // Take the cursor out of any add field so the arrow keys reach the list.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Asks for a rename. The row opens its field when `editingID` arrives, so
    /// the keyboard (return on a selected task) goes through the same path.
    private func beginEdit() {
        window.editingID = todo.id
    }

    private func openEdit() {
        guard !hasOpenEdit else { return }
        hasOpenEdit = true
        draft = todo.title
        // Focus has to wait until the field actually exists in the view tree.
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        guard hasOpenEdit else { return }
        hasOpenEdit = false
        store.rename(todo, to: draft)
        if window.editingID == todo.id { window.editingID = nil }
    }

    private func cancelEdit() {
        hasOpenEdit = false
        if window.editingID == todo.id { window.editingID = nil }
    }

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}
