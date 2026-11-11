import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare binary via `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        OutsideClick.install()
        Feedback.preload()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}


struct DevTasksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @AppStorage("appearance") private var appearance: Appearance = .dark

    init() { FA.register() }

    var body: some Scene {
        Window("DevTasks", id: "main") {
            ThemeProvider { RootView() }
                .environmentObject(store)
                .onAppear { appearance.apply() }
                .onChange(of: appearance) { _, new in new.apply() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.showNotes = false; store.focusQuickAdd += 1 }
                    .keyboardShortcut("n")
                Button("New Note") { store.newNote() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Lists") {
                ForEach(Bucket.allCases) { b in
                    Button(b.title) { store.selected = b; store.showNotes = false }
                        .keyboardShortcut(KeyEquivalent(b.key))
                }
                Divider()
                Button("Scratchpad") { store.showNotes = true }
                    .keyboardShortcut("5")
            }
            CommandGroup(after: .sidebar) {
                Button("Cycle Appearance") { appearance = appearance.next }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            ThemeProvider(translucent: false) { SettingsRoot() }
        }
    }
}

private struct SettingsRoot: View {
    @Environment(\.theme) private var t
    var body: some View { ThemeSettings().background(t.panel) }
}
