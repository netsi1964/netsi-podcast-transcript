import SwiftUI
import AppKit

/// When the app is launched as a bare SwiftPM executable (no `.app` bundle), macOS defaults its
/// activation policy to `.prohibited`, so no window or Dock icon ever appears. Forcing `.regular`
/// and activating makes the UI show. A packaged `.app` sets this via Info.plist instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Give the bare SwiftPM binary a real Dock icon.
        NSApp.applicationIconImage = AppIcon.image()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PodcastTranscriptStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        // Fall back to an in-memory store if the on-disk database can't be opened, so the app
        // still launches rather than crashing (PRD-SEC-006 resilience).
        let store: Store
        do {
            store = try Store(url: try Store.defaultDatabaseURL())
        } catch {
            store = (try? Store.inMemory()) ?? { fatalError("Kan ikke oprette database: \(error)") }()
        }
        _model = StateObject(wrappedValue: AppModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { model.bootstrap() }
        }
        .commands {
            SidebarCommands()
            // Replace the default "About" menu item with our own window.
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }

        Window("Om Podcast Transcript Studio", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

/// The "About" app-menu item; opens the custom About window.
private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Om Podcast Transcript Studio") { openWindow(id: "about") }
    }
}
