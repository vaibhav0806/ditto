import AppKit
import SwiftUI
import ServiceManagement
import DittoCore

final class Preferences: ObservableObject {
    @Published var captureEnabled: Bool { didSet { defaults.set(captureEnabled, forKey: "captureEnabled") } }
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays") } }
    @Published var excludedApps: String { didSet { defaults.set(excludedApps, forKey: "excludedApps") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureEnabled = InputPolicy.captureEnabled(saved: defaults.object(forKey: "captureEnabled") as? Bool)
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 7
        excludedApps = defaults.string(forKey: "excludedApps") ?? "com.1password.1password\ncom.agilebits.onepassword7\ncom.apple.keychainaccess"
    }

    var exclusions: Set<String> {
        Set(excludedApps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var error = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onClear: () -> Void

    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Capture copied text", isOn: $preferences.captureEnabled)
                Picker("Keep unpinned history", selection: $preferences.retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                Text("Stored on this Mac. Pinned items stay until you remove them.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded apps") {
                Text("One app bundle identifier per line. Capture and suggestions are disabled in these apps.").font(.caption)
                TextEditor(text: $preferences.excludedApps).font(.system(.body, design: .monospaced)).frame(height: 100)
            }
            Section("Startup") {
                Toggle("Launch Ditto at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = ""
                    } catch {
                        self.error = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            }
            Section {
                Text("Invoke ⌥⌘V · Accept Tab · History ⌘L · Close Esc").font(.caption)
                Button("Clear all history…", role: .destructive, action: onClear)
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }.formStyle(.grouped).padding(12).frame(width: 480, height: 570)
    }
}
