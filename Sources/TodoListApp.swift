import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// The shortcut that summons the window from any app. ⌃⌥⌘T: T for todo.
/// Plain ⌃⌥ letters are taken by window tilers such as SnappyTiler.
enum Summon {
    static let keyCode = kVK_ANSI_T
    static let modifiers = controlKey | optionKey | cmdKey
    static let label = "⌃⌥⌘T"
}

/// Owns the long-lived pieces so the global hotkey and the key monitor can
/// reach them even while the window is closed.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let store = TodoStore()
    let window = WindowState()

    private var hotKey: GlobalHotKey?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(keyCode: Summon.keyCode, modifiers: Summon.modifiers) { [weak self] in
            self?.toggleWindow()
        }
        // Only catches clashes macOS reports. Another app's shortcut usually
        // isn't, and whichever app registered first silently wins.
        if hotKey == nil {
            let alert = NSAlert()
            alert.messageText = "\(Summon.label) is already in use"
            alert.informativeText = "Another app has claimed \(Summon.label), so it won't bring up Todo List. "
                + "Change Summon in TodoListApp.swift and rebuild to pick a different shortcut."
            alert.runModal()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.window.handleKey(event, store: self.store) ? nil : event
        }

        LoginItem.enableOnFirstLaunch()
    }

    /// Stay running with the window closed, so the hotkey still works. ⌘Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showWindow() }
        return true
    }

    /// Frontmost with the window up: tuck it away. Otherwise bring it forward,
    /// reopening it if it was closed.
    private func toggleWindow() {
        if NSApp.isActive, mainWindow?.isVisible == true {
            NSApp.hide(nil)
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        NSApp.unhide(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
        } else {
            window.reopenWindow?()
        }
    }

    /// The task window, ignoring panels, alerts, and menus.
    private var mainWindow: NSWindow? {
        NSApp.windows.first { ($0.identifier?.rawValue.hasPrefix(TodoListApp.windowID) ?? false) && $0.canBecomeMain }
    }
}

/// "Open at Login", via the system's login item service.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
                + "\n\nYou can also manage it in System Settings ▸ General ▸ Login Items."
            alert.runModal()
        }
    }

    /// A hotkey only helps if the app is running, so turn this on once. After
    /// that the menu toggle and System Settings decide.
    static func enableOnFirstLaunch() {
        let key = "loginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !isEnabled { try? SMAppService.mainApp.register() }
    }
}

@main
struct TodoListApp: App {
    static let windowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var opensAtLogin = LoginItem.isEnabled

    var body: some Scene {
        // A single Window rather than a WindowGroup: closing it keeps the app
        // running, and there is only ever one to bring back.
        Window("Todo List", id: Self.windowID) {
            ContentView()
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.window)
        }
        .defaultSize(width: 480, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Toggle("Open at Login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { LoginItem.set($0); opensAtLogin = LoginItem.isEnabled }))
            }

            // Each shortcut switches to the right view and drops the cursor in
            // that field, so a task can be filed without touching the mouse.
            CommandMenu("Add Task") {
                ForEach(Array(Bucket.allCases.enumerated()), id: \.element) { index, bucket in
                    Button("New \(bucket.singular)") { appDelegate.window.target = .bucket(bucket) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                          modifiers: .command)
                }
                Divider()
                Button("New Long-Term Task") { appDelegate.window.target = .longTerm }
                    .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
