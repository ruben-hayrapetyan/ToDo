import AppKit
import Combine
import SwiftUI

/// Where a keyboard shortcut wants to put the cursor.
enum FocusTarget: Equatable {
    case bucket(Bucket)
    case longTerm
}

/// The window's view state that more than one view — or the app delegate —
/// needs to reach: the filter, which task is selected or being renamed, and
/// "put the cursor in that field" requests from menu commands.
final class WindowState: ObservableObject {
    /// Set it, the matching add field claims focus, then clears it.
    @Published var target: FocusTarget?
    @Published var filter: Filter = .all
    /// The selected tasks and the one the arrow keys are on. Drawn highlighted.
    @Published var selection = Selection()
    /// The task whose title is open for renaming.
    @Published var editingID: UUID?
    /// Set to a task to open its due-date popover (the D key); the row opens
    /// it and clears this.
    @Published var dueRequest: UUID?

    /// Brings the window back after it has been closed. Captured from SwiftUI's
    /// `openWindow` by the first view, since the app delegate has no other way in.
    var reopenWindow: (() -> Void)?

    /// Mirrors ContentView's @AppStorage, read directly so key handling does not
    /// need a view.
    var page: Page {
        Page(rawValue: UserDefaults.standard.string(forKey: "selectedHorizon") ?? "") ?? .shortTerm
    }

    /// What an action on this task's row should cover: the whole selection
    /// when the task is part of a larger one, otherwise just the task.
    func targets(for todo: Todo, in store: TodoStore) -> [Todo] {
        guard selection.contains(todo.id), selection.count > 1 else { return [todo] }
        return selection.chosen(from: store.visibleItems(in: page, filter: filter))
    }

    // MARK: - Keyboard

    /// Handles a key press aimed at the task list. Returns false to let it pass
    /// through — always the case while a text field has the cursor, so typing is
    /// never intercepted.
    ///
    ///   ↑ ↓      move the selection      ⇧↑ ⇧↓    select a run
    ///   ⌘A       select every task       esc      clear the selection
    ///   space    done / not done         s        star
    ///   1 2 3    ¼ ½ ¾ of the way        0        clear progress
    ///   d        set a due date          return   rename
    ///   ⌫        delete (⌘Z undoes)
    ///
    /// Everything but rename acts on the whole selection.
    func handleKey(_ event: NSEvent, store: TodoStore) -> Bool {
        guard let window = event.window, window.isKeyWindow,
              !(window.firstResponder is NSText) else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let visible = store.visibleItems(in: page, filter: filter)
        let order = visible.map(\.id)

        if modifiers == .command {
            guard key == "a", !order.isEmpty else { return false }
            selection.selectAll(order)
            return true
        }
        guard modifiers.subtracting(.shift).isEmpty else { return false }

        let chosen = selection.chosen(from: visible)
        // The selected task the keys start from: the cursor's, unless ⌘-click
        // just dropped it from the selection.
        let current = selection.cursor.flatMap { id in chosen.first { $0.id == id } } ?? chosen.first

        switch Int(event.keyCode) {
        case 125:   // down
            selection.move(by: 1, in: order, extending: modifiers == .shift)
        case 126:   // up
            selection.move(by: -1, in: order, extending: modifiers == .shift)
        case 49:    // space
            guard let current = current else { return false }
            store.setDone(chosen, !current.isDone)
            // Finishing a task moves it to the bottom; the selection follows it.
        case 36, 76:   // return, keypad enter
            guard let current = current else { return false }
            editingID = current.id
        case 51, 117:  // delete, forward delete
            guard let first = chosen.first,
                  let i = visible.firstIndex(where: { $0.id == first.id }) else { return false }
            store.delete(chosen)
            // Land on the neighbour so several can be deleted in a row.
            let rest = store.visibleItems(in: page, filter: filter)
            if rest.isEmpty { selection.clear() } else { selection.select(rest[min(i, rest.count - 1)].id) }
        case 53:    // escape
            guard !selection.isEmpty else { return false }
            selection.clear()
        default:
            guard let current = current, modifiers.isEmpty else { return false }
            switch key {
            case "s":
                store.setStarred(chosen, !current.isStarred)
            case "d":
                dueRequest = current.id
            case let digit? where digit.count == 1 && Int(digit).map(Todo.quarters.contains) == true:
                store.setProgress(chosen, to: Int(digit)!)
            default:
                return false
            }
        }
        return true
    }
}
