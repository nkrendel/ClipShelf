import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(Settings.Key.maxHistory) private var maxHistory = 100
    @AppStorage(Settings.Key.pasteAfterSelect) private var pasteAfterSelect = true
    @AppStorage(Settings.Key.inlineCount) private var inlineCount = 0
    @AppStorage(Settings.Key.folderSize) private var folderSize = 10
    @AppStorage(Settings.Key.titleLength) private var titleLength = 40
    @AppStorage(Settings.Key.numberItems) private var numberItems = true
    @AppStorage(Settings.Key.markOtherDeviceClips) private var markOtherDeviceClips = true
    @AppStorage(Settings.Key.previewDelay) private var previewDelay = 2.0
    @AppStorage(Settings.Key.storeText) private var storeText = true
    @AppStorage(Settings.Key.storeRichText) private var storeRichText = true
    @AppStorage(Settings.Key.storeFiles) private var storeFiles = true
    @AppStorage(Settings.Key.storeURLs) private var storeURLs = true
    @AppStorage(Settings.Key.storeImages) private var storeImages = true
    @AppStorage(Settings.Key.storePDF) private var storePDF = true

    @State private var excluded: [String] = Settings.defaults.stringArray(forKey: Settings.Key.excludedBundleIDs) ?? []
    @State private var selectedExcluded: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = Paster.isTrusted

    var onLimitChange: () -> Void = {}

    var body: some View {
        Form {
            Section("History") {
                Stepper("Keep \(maxHistory) items", value: $maxHistory, in: 10...1000, step: 10)
                    .onChange(of: maxHistory) { onLimitChange() }
                Toggle("Mark items copied on another device", isOn: $markOtherDeviceClips)
                Text("Copies from your other Macs arrive through macOS Universal Clipboard (same Apple Account, Handoff on, Bluetooth and Wi-Fi on).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Store these types") {
                Toggle("Plain text", isOn: $storeText)
                Toggle("Rich text (RTF/RTFD)", isOn: $storeRichText)
                Toggle("Files", isOn: $storeFiles)
                Toggle("Web links", isOn: $storeURLs)
                Toggle("Images", isOn: $storeImages)
                Toggle("PDF", isOn: $storePDF)
            }

            Section("Menu") {
                Stepper("Show \(inlineCount) items before folders", value: $inlineCount, in: 0...50)
                Stepper("\(folderSize) items per folder", value: $folderSize, in: 5...50, step: 5)
                Stepper("Titles up to \(titleLength) characters", value: $titleLength, in: 10...120, step: 5)
                Toggle("Number the items", isOn: $numberItems)
                Picker("Preview items", selection: $previewDelay) {
                    Text("Never").tag(-1.0)
                    Text("Immediately").tag(0.0)
                    ForEach([0.5, 1, 2, 3, 5], id: \.self) { seconds in
                        Text("After \(seconds.formatted()) s").tag(seconds)
                    }
                }
                LabeledContent("Open the menu", value: "⌃⌘V")
            }

            Section("Pasting") {
                Toggle("Paste into the current app after choosing an item", isOn: $pasteAfterSelect)
                HStack {
                    Text(accessibilityGranted ? "Accessibility access granted" : "Needs Accessibility access to paste")
                        .foregroundStyle(accessibilityGranted ? Color.secondary : Color.orange)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant Access…") {
                            Paster.requestTrust()
                        }
                    }
                }
            }

            Section("Ignore copies from these apps") {
                List(excluded, id: \.self, selection: $selectedExcluded) { id in
                    Text(id).font(.system(.body, design: .monospaced))
                }
                .frame(minHeight: 90)
                HStack {
                    Button("Add App…", action: addExcludedApp)
                    Button("Remove") {
                        excluded.removeAll { $0 == selectedExcluded }
                        selectedExcluded = nil
                        saveExcluded()
                    }
                    .disabled(selectedExcluded == nil)
                }
                Text("Copies that apps mark as private (most password managers do) are always ignored.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityGranted = Paster.isTrusted
        }
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !excluded.contains(id) {
                excluded.append(id)
            }
        }
        saveExcluded()
    }

    private func saveExcluded() {
        Settings.defaults.set(excluded, forKey: Settings.Key.excludedBundleIDs)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ClipShelf: launch at login change failed: %@", String(describing: error))
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
