import Foundation

/// Which tasks are selected in the list, and where the keyboard is.
///
/// Plain values with no UI, so the click and arrow-key rules can be tested:
/// a click picks one task, ⌘-click adds or drops one, ⇧-click and ⇧↑/↓ select
/// the run between the anchor and the task reached.
struct Selection: Equatable {
    private(set) var ids: Set<UUID> = []
    /// The task the arrow keys move from, and the one kept on screen.
    private(set) var cursor: UUID?
    /// Where a ⇧-extended run starts.
    private(set) var anchor: UUID?

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// The selected tasks among those given, in the order given.
    func chosen(from items: [Todo]) -> [Todo] {
        items.filter { ids.contains($0.id) }
    }

    /// Just this task.
    mutating func select(_ id: UUID) {
        ids = [id]
        cursor = id
        anchor = id
    }

    /// ⌘-click: adds the task, or drops it if it was already selected.
    mutating func toggle(_ id: UUID) {
        if ids.contains(id) {
            ids.remove(id)
            if ids.isEmpty { clear(); return }
        } else {
            ids.insert(id)
        }
        cursor = id
        anchor = id
    }

    /// ⇧-click: everything from the anchor to this task, in on-screen order.
    /// With no anchor on screen it is an ordinary click.
    mutating func extend(to id: UUID, in order: [UUID]) {
        guard let from = anchor.flatMap({ order.firstIndex(of: $0) }),
              let to = order.firstIndex(of: id) else { select(id); return }
        ids = Set(order[min(from, to)...max(from, to)])
        cursor = id
    }

    mutating func selectAll(_ order: [UUID]) {
        guard let first = order.first else { return }
        ids = Set(order)
        anchor = first
        cursor = order.last
    }

    mutating func clear() {
        ids = []
        cursor = nil
        anchor = nil
    }

    /// ↑ / ↓: moves the cursor one step, selecting just that task, or with ⇧
    /// growing the run from the anchor. With nothing selected, ↓ lands on the
    /// first task and ↑ on the last.
    mutating func move(by step: Int, in order: [UUID], extending: Bool) {
        guard !order.isEmpty else { return }
        let target: Int
        if let i = cursor.flatMap({ order.firstIndex(of: $0) }) {
            target = min(max(i + step, 0), order.count - 1)
        } else {
            target = step > 0 ? 0 : order.count - 1
        }
        if extending, !isEmpty {
            extend(to: order[target], in: order)
        } else {
            select(order[target])
        }
    }
}
