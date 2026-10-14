# Todo List — a native macOS app

A small, self-contained Mac app: SwiftUI front end, JSON storage on disk, no
dependencies and no Xcode project. It builds with the Swift compiler that ships
with the Command Line Tools.

<p align="center">
  <img src="docs/demo.gif" width="420" alt="Adding a task, starring it, and marking another one done">
</p>

<p align="center"><sub>Preview rendered from the app's own colors, type, and layout rules (<code>Sources/DesignSystem.swift</code>) — sample data, not a real task list.</sub></p>

## Build

```bash
./build.sh
```

This produces `build/Todo List.app`, renders the app icon, writes `Info.plist`,
and ad-hoc signs the bundle. To install it, run:

```bash
./build.sh --install
```

That quits any running copy, replaces `/Applications/Todo List.app`, and
launches it. Run the installed copy rather than the one in `build/`. The login
item remembers where the app is, and `build/` is wiped on every build.

## Test

```bash
./test.sh
```

Compiles the model and store with `Tests/main.swift` and runs the checks.
These are plain assertions rather than XCTest, so the tests need only the
Command Line Tools, like the app.

## Using it

**⌃⌥Space** (Control-Option-Space) brings the window up from any app, and hides it
again if it is already in front. For that to work the app has to be running, so:

- Closing the window keeps the app running. Only **⌘Q** quits.
- On first launch the app adds itself to your login items. Turn that off with
  **Todo List ▸ Open at Login**, or in System Settings ▸ General ▸ Login Items.
- To use a different shortcut, change `Summon` in `Sources/TodoListApp.swift`
  and rebuild. macOS usually doesn't report a clash with another app's
  shortcut. If pressing it does nothing, or does something else, another app
  holds it, so pick a different one.

A **Short Term / Long Term / Due** toggle sits at the top of the window. Short term is
the sectioned view — **Readings**, **Assignments**, **Emails**, and **Other**,
stacked on one screen. Long term is a single flat list with no sections. Each has its own add field, so a task goes straight into
the section you typed it in.

**Due** shows only tasks with a due date, from both short and long term, in the
order they fall due: overdue first, then soonest to latest. Each row starts
with where the task lives (`READ` `ASGN` `MAIL` `MISC`, or `LONG`) and keeps its
own ink. Finished tasks still drop to the bottom. There is no add field here: a
task appears as soon as you give it a date, and leaves if you remove it.

- Type in a section's field and press **Return** to add a task there. Focus
  stays put, so you can add several in a row.
- **⌘1 / ⌘2 / ⌘3 / ⌘4** put the cursor straight into the Readings, Assignments,
  Emails, or Other field, and **⌘L** into the long-term one — no mouse needed.
  A shortcut aimed at the view you are not on switches to it first. Each field
  shows its own shortcut while idle, and the commands live in the **Add Task**
  menu.
- Click the box to mark a task done. Finished tasks drop to the bottom of
  their section and the section's count badge updates.
- Click the **star** (it appears on hover) to flag a task. It stays lit where it
  sits; use the **Starred** filter to pull the flagged ones together.
- Click the **calendar** (it appears on hover) or right-click ▸ **Set Due Date…**
  to give a task a deadline. A day or more out it shows the date; under a day it
  becomes a live **countdown**; once it passes it turns **red** and counts up from
  `+0s` in weeks, days, hours, minutes and seconds, showing the three largest
  (`+5m 6s`, `+3d 4h 5m`, `+1w 1d 3h`). Finished tasks just show the date.
- **Part done?** Click the **pie** (it appears on hover) to add a quarter:
  ¼ → ½ → ¾ → back to none. Or select a task and press **1 / 2 / 3**, with
  **0** to clear. The box fills with ink from the bottom to match, so a section
  shows how far along everything is. Ticking the box still finishes the task,
  and unticking it puts the quarters back. Part-done tasks count as open.
- **One due date for many tasks:** select them (**⌘-click** to add one,
  **⇧-click** or **⇧↑ / ⇧↓** for a run, **⌘A** for everything on screen), then
  press **D**, click the calendar on any of them, or right-click ▸ **Set Due
  Date for N Tasks…**. To date a whole section, hover its header and click the
  calendar, or right-click it ▸ **Set Due Date for Every Open Assignment…**.
  Either way, one **⌘Z** undoes the lot.
- Within a section tasks are **alphabetical**, with finished ones moved to the
  bottom. Stars do not change the order. Sorting ignores case and reads embedded
  numbers as numbers, so "Chapter 3" comes before "Chapter 11".
- **Double-click** a task to rename it. **Return** saves, **Esc** cancels.
  Renaming to an empty string deletes the task.
- Hover and click the **×** to delete; right-click for the same actions in a
  context menu.
- **⌘Z** undoes anything: a delete, a rename, a tick, Clear Completed.
  **⇧⌘Z** redoes.
- **Click a task** to select it, then use the keyboard: **↑ / ↓** move, **Space**
  ticks it, **1–3 / 0** set progress, **D** sets a due date, **Return** renames,
  **S** stars, **⌫** deletes, and **Esc** clears the selection. With several
  selected, every key but Return acts on all of them, and so do the buttons on
  any selected row. In an add field, **Esc** leaves the field so these keys reach the
  list.
- **Unstar all** in the footer takes the star off every task in the view you are
  on (on **Due**, every dated task). It then turns into **Restore stars**, which puts back exactly the ones it
  removed - so a mis-click costs nothing. Starring anything by hand, or
  relaunching, retires the undo and the control reads "Unstar all" again.
- **All / Active / Starred / Done** filters whatever is on screen.
  **Clear Completed** removes finished tasks from the view you are on only, so
  clearing short term never touches long term, and clearing **Due** removes
  only finished tasks that had a date.
- Every change is written to disk the moment you make it, so quitting never
  loses anything.

## Screenshots

<table>
<tr>
<td align="center" width="50%">
  <img src="docs/short-term-light.png" width="380" alt="Short term view, light mode: Readings, Assignments, Emails, and Other sections">
  <br><sub>Short term — light</sub>
</td>
<td align="center" width="50%">
  <img src="docs/short-term-dark.png" width="380" alt="Short term view, dark mode">
  <br><sub>Short term — dark</sub>
</td>
</tr>
<tr>
<td align="center" colspan="2">
  <img src="docs/long-term-light.png" width="380" alt="Long term view: a single flat list with no sections">
  <br><sub>Long term — one flat list, no sections</sub>
</td>
</tr>
</table>

## Where the data lives

```
~/Documents/Todo List/todos.json
```

A visible folder on purpose: `~/Library/Application Support` is hidden and
protected, so Finder would not show the file and folder pickers in other apps
refused it. Task files still in the old location are moved there automatically
on first launch.

Plain JSON, rewritten atomically after every change. Delete that file to start
over; copy it to move your tasks to another Mac. Older task files still load:
tasks saved before sections existed land in **Assignments**, and tasks saved
before the short/long term split count as **short term**.

The app never overwrites a file it couldn't read. A banner at the top of the
window explains any problem:

- **The file isn't valid JSON.** It is renamed to `todos.unreadable-<time>.json`
  in the same folder, and the app starts with an empty list.
- **Some tasks can't be read.** The app loads the rest and first copies the
  original to `todos.unreadable-<time>.json`.
- **The file can't be opened**, usually because macOS denied access to
  Documents. Saving is switched off, so the file isn't touched.
- **A save fails.** The banner says so until a later save succeeds.

## Layout

| Path                        | What it is                                          |
| --------------------------- | --------------------------------------------------- |
| `Sources/Todo.swift`        | `Todo`, the `Horizon` split, `Page`, `Bucket`, `Filter` |
| `Sources/TodoStore.swift`   | Task list + load/save, the single source of truth   |
| `Sources/DesignSystem.swift`| The palette and the three type roles                |
| `Sources/ContentView.swift` | Window chrome, sections, the long-term and due lists, rows |
| `Sources/WindowState.swift` | Filter, selection, rename state; list keyboard keys |
| `Sources/Selection.swift`   | Click, ⌘-click and ⇧-range selection rules          |
| `Sources/GlobalHotKey.swift`| The system-wide ⌃⌥Space shortcut                       |
| `Sources/TodoListApp.swift` | App entry point, window, menus, open at login       |
| `Tests/main.swift`          | Store and file-format tests, run by `test.sh`       |
| `tools/MakeIcon.swift`      | Draws the icon into an `.iconset` at build time     |
| `build.sh`                  | Compiles, assembles, signs, and optionally installs |
| `test.sh`                   | Builds and runs the tests                           |

## The design

The app is a notebook, and the visual system follows from that.

**Two inks.** Colour marks *when*, not *what*: short-term tasks are written in
iron-gall navy, long-term ones in aged sepia. Sections are told apart by their
code, never by a colour of their own, so the window never turns into a rainbow.

**Four-letter codes.** `READ` `ASGN` `MAIL` `MISC` are all exactly four
characters, so in a monospaced face they set a true column down the page. The
rule running from each code to its count carries the eye between the two.

**The ruled margin.** A hairline runs down the list between the checkbox and the
text. Starring a task thickens that segment into a gold marginal mark — the way
you would flag a line in a real notebook. That is why starring can leave the
alphabetical order alone and still make a task stand out.

**Three faces, one job each.** New York for the wordmark, SF Mono for codes,
counts and shortcuts, SF Pro for the tasks themselves — the only text that is
arbitrary. All three ship with macOS, so nothing is bundled.

The icon is the same idea in miniature: a sheet of ruled paper, the margin in
aged sepia, a check struck in fresh navy. Below 64px the ruling and margin drop
away and the check recentres, so it stays legible in the Dock.
