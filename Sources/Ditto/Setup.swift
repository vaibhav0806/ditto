import AppKit
import SwiftUI
import ApplicationServices

final class SetupModel: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var input = CGPreflightListenEventAccess()
    @Published var status = "Copy text, then invoke Ditto with ⌥⌘V."
    func refresh() {
        accessibility = AXIsProcessTrusted()
        input = CGPreflightListenEventAccess()
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var preferences: Preferences
    var enableCapture: () -> Void
    var openPractice: () -> Void
    var openHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 34)).foregroundStyle(Color.accentColor)
            Text("Meet Ditto.").font(.largeTitle.bold())
            Text("Copy once. There when you need it.").foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("1 · Allow text insertion").font(.headline)
                Text("Accessibility lets Ditto locate the cursor and replace only the query you typed. It does not save your document or typing.").font(.callout).foregroundStyle(.secondary)
                Button(model.accessibility ? "Accessibility allowed ✓" : "Allow Accessibility…") {
                    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("2 · Allow session keyboard controls").font(.headline)
                Text("If macOS requires it, enable Input Monitoring for Tab, arrows, and Escape. Ditto processes these controls only during paste mode.").font(.callout).foregroundStyle(.secondary)
                Button(model.input ? "Input Monitoring allowed ✓" : "Open Input Monitoring…") {
                    _ = CGRequestListenEventAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("3 · Start local clipboard history").font(.headline)
                Text("Saved only on this Mac for \(preferences.retentionDays) days. You can pause, exclude apps, or delete history at any time. macOS may ask you to allow clipboard access.").font(.callout).foregroundStyle(.secondary)
                Button(preferences.captureEnabled ? "Check / enable clipboard access" : "Enable clipboard capture", action: enableCapture)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try in a practice field", action: openPractice).buttonStyle(.borderedProminent)
                Button("Open History", action: openHistory)
            }
        }.padding(28).frame(width: 510)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in model.refresh() }
    }
}
