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
    /// The task the arrow keys are on. Drawn highlighted.
    @Published var selectedID: UUID?
    /// The task whose title is open for renaming.
    @Published var editingID: UUID?

    /// Brings the window back after it has been closed. Captured from SwiftUI's
    /// `openWindow` by the first view, since the app delegate has no other way in.
    var reopenWindow: (() -> Void)?

    /// Mirrors ContentView's @AppStorage, read directly so key handling does not
    /// need a view.
    var horizon: Horizon {
        Horizon(rawValue: UserDefaults.standard.string(forKey: "selectedHorizon") ?? "") ?? .shortTerm
    }

    // MARK: - Keyboard

    /// Handles a key press aimed at the task list. Returns false to let it pass
    /// through — always the case while a text field has the cursor, so typing is
    /// never intercepted.
    ///
    ///   ↑ ↓      move the selection      space    done / not done
    ///   return   rename                  s        star
    ///   ⌫        delete (⌘Z undoes)      esc      clear the selection
    func handleKey(_ event: NSEvent, store: TodoStore) -> Bool {
        guard let window = event.window, window.isKeyWindow,
              !(window.firstResponder is NSText),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }

        let visible = store.visibleItems(in: horizon, filter: filter)
        let index = selectedID.flatMap { id in visible.firstIndex { $0.id == id } }
        let selected = index.map { visible[$0] }

        switch Int(event.keyCode) {
        case 125:   // down
            guard !visible.isEmpty else { return true }
            selectedID = visible[index.map { min($0 + 1, visible.count - 1) } ?? 0].id
        case 126:   // up
            guard !visible.isEmpty else { return true }
            selectedID = visible[index.map { max($0 - 1, 0) } ?? visible.count - 1].id
        case 49:    // space
            guard let todo = selected else { return false }
            store.toggle(todo)
            // Finishing a task moves it to the bottom; stay on it.
        case 36, 76:   // return, keypad enter
            guard let todo = selected else { return false }
            editingID = todo.id
        case 51, 117:  // delete, forward delete
            guard let todo = selected, let i = index else { return false }
            store.delete(todo)
            // Land on the neighbour so several can be deleted in a row.
            let rest = store.visibleItems(in: horizon, filter: filter)
            selectedID = rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
        case 53:    // escape
            guard selectedID != nil else { return false }
            selectedID = nil
        default:
            guard event.charactersIgnoringModifiers?.lowercased() == "s",
                  let todo = selected else { return false }
            store.toggleStar(todo)
        }
        return true
    }
}
