import SwiftUI
import AppKit

enum SettingsTab: Hashable {
    case general
    case transcription
    case about
}

/// Settings window view
struct SettingsView: View {
    
    @ObservedObject var settings = AppSettings.shared
    @EnvironmentObject private var modelManager: AIModelManager
    @State private var selectedTab: SettingsTab

    init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettings(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)
            
            TranscriptionSettings()
                .environmentObject(modelManager)
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(SettingsTab.transcription)

            AboutSettings()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 500, idealWidth: 500, maxWidth: 700, minHeight: 540, idealHeight: 540)
    }
}

// MARK: - General Settings

struct GeneralSettings: View {
    
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        Form {
            Section {
                Picker("Recording button:", selection: $settings.recordingPanelPosition) {
                    ForEach(AppSettings.RecordingPanelPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.menu)

                Picker("Date/Time Format:", selection: $settings.dateTimeFormat) {
                    ForEach(AppSettings.DateTimeFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                
                if settings.dateTimeFormat == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Custom format pattern", text: $settings.customDateFormat)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("ℹ️ Use DateFormatter patterns (d=day, M=month, y=year, H=hour, m=minute)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Preview
                HStack {
                    Text("Preview:")
                        .foregroundStyle(.secondary)
                    Text(settings.formatDate(Date()))
                        .fontWeight(.medium)
                }
                .font(.callout)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarIcon)
                        .disabled(appDelegate.isRecording || appDelegate.isFinalizingRecording)
                    Text("Disables quick access from the menu bar icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if appDelegate.isRecording || appDelegate.isFinalizingRecording {
                        Text("Cannot be changed while recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Auto-delete recordings older than")
                        TextField("", value: $settings.autoDeleteAfterDays, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .multilineTextAlignment(.center)
                        Text("days")
                    }
                    Text("Automatically deletes recordings and their audio files. Set to 0 to disable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("General", systemImage: "gearshape")
                    .font(.headline)
            }
            CLIAPISection(settings: settings, appDelegate: appDelegate)

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Ask for App Store review", isOn: $settings.reviewPromptsEnabled)
                    Text("Occasionally prompts to rate the app after you've used it for a while.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Check for updates automatically", isOn: $settings.updatesCheckEnabled)
                    Text("Checks App Store for a newer version every \(AppSettings.updateCheckIntervalDays) days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Feedback", systemImage: "star")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Transcription Settings (Placeholder)

struct TranscriptionSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var modelManager: AIModelManager
    @State private var hoveredLockedModelID: String?
    @State private var showLanguageSheet = false
    @State private var showModelSheet = false
    @State private var activeDownloadErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                visibleLanguagesSection
                modelsSection

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Default model")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Default model", selection: $settings.defaultTranscriptionModelID) {
                                ForEach(modelManager.transcriptionModels.filter { modelManager.isInstalled($0.id) }) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Default language")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Default language", selection: $settings.transcriptionLanguage) {
                                ForEach(AppSettings.TranscriptionLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Split Audio Labels")
                            Spacer()
                        }
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Microphone label")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Microphone", text: $settings.micSourceName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("System Audio label")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("System Audio", text: $settings.systemSourceName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Unload model from memory after transcription")
                            Spacer()
                            Toggle("", isOn: $settings.unloadModelAfterTranscription)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        Text("Reduces RAM usage, especially with large models. May increase startup time for the next transcription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("This affects memory only. Downloaded models remain on disk and do not need to be re-downloaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(10)

            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            modelManager.refreshInstalledTranscriptionModelsFromDisk()
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transcription Models", systemImage: "waveform.and.mic")
                .font(.headline)

            HStack {
                Text(installedModelsPreview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Manage…") {
                    showModelSheet = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(10)
        }
        .sheet(isPresented: $showModelSheet) {
            modelManagementSheet
        }
    }

    private var installedModelsPreview: String {
        let installed = modelManager.transcriptionModels.filter { modelManager.isInstalled($0.id) }
        guard !installed.isEmpty else { return "No models installed" }
        let maxShown = 2
        let shown = installed.prefix(maxShown).map { $0.displayName }.joined(separator: ", ")
        let remaining = installed.count - maxShown
        if remaining > 0 { return "\(shown) +\(remaining) more" }
        return shown
    }

    @ViewBuilder
    private var modelManagementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcription Models")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { showModelSheet = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                Text("Disk is approximate model size on storage. RAM is approximate memory usage during transcription.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(modelManager.transcriptionModels) { model in
                        modelCard(model)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 460)
        .onAppear {
            modelManager.refreshInstalledTranscriptionModelsFromDisk()
        }
        .onChange(of: modelManager.downloadErrorByModelID) { _, newErrors in
            activeDownloadErrorMessage = newErrors.values.first
        }
        .alert(
            "Download Error",
            isPresented: Binding(
                get: { activeDownloadErrorMessage != nil },
                set: { isPresented in if !isPresented { activeDownloadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { activeDownloadErrorMessage = nil }
        } message: {
            Text(activeDownloadErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var visibleLanguagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Visible Languages", systemImage: "globe")
                .font(.headline)

            Text("Choose which languages appear in the transcription picker for each recording.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(visibleLanguagesPreview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Manage…") {
                    showLanguageSheet = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(10)
        }
        .sheet(isPresented: $showLanguageSheet) {
            languageManagementSheet
        }
    }

    private var visibleLanguagesPreview: String {
        let sorted = AppSettings.allNonAutoLanguages.filter { settings.visibleLanguageIDs.contains($0.rawValue) }
        guard !sorted.isEmpty else { return "None selected" }
        let maxShown = 3
        let shown = sorted.prefix(maxShown).map { $0.displayName }.joined(separator: ", ")
        let remaining = sorted.count - maxShown
        if remaining > 0 {
            return "\(shown) +\(remaining) more"
        }
        return shown
    }

    @ViewBuilder
    private var languageManagementSheet: some View {
        let allLanguages = AppSettings.allNonAutoLanguages
        let count = allLanguages.count
        let colSize = Int(ceil(Double(count) / 3.0))
        let col1 = Array(allLanguages[0..<min(colSize, count)])
        let col2 = Array(allLanguages[min(colSize, count)..<min(colSize * 2, count)])
        let col3 = Array(allLanguages[min(colSize * 2, count)..<count])

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Visible Languages")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Select All") {
                    settings.visibleLanguageIDs = Set(allLanguages.map { $0.rawValue })
                }
                .buttonStyle(.bordered)
                Button("Deselect All") {
                    settings.visibleLanguageIDs = []
                }
                .buttonStyle(.bordered)
            }

            Text("Auto is always shown. Manage which other languages appear in the per-recording picker.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                languageColumn(col1)
                languageColumn(col2)
                languageColumn(col3)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    showLanguageSheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private func languageColumn(_ languages: [AppSettings.TranscriptionLanguage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(languages) { language in
                Toggle(language.displayName, isOn: Binding(
                    get: { settings.visibleLanguageIDs.contains(language.rawValue) },
                    set: { isOn in
                        if isOn {
                            settings.visibleLanguageIDs.insert(language.rawValue)
                        } else {
                            settings.visibleLanguageIDs.remove(language.rawValue)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func modelCard(_ model: AIModelDescriptor) -> some View {
        HStack(spacing: 10) {
            if !modelManager.isDownloading(model.id) && modelManager.isInstalled(model.id) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text(model.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)

            if let lang = model.lockedLanguage {
                Text("(\(lang.uppercased()) only)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(diskInfoLabel(for: model)) • RAM \(model.memoryLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if modelManager.isDownloading(model.id) {
                HStack(spacing: 8) {
                    ProgressView(value: modelManager.progress(for: model.id))
                        .frame(width: 72)
                    Text("\(Int(modelManager.progress(for: model.id) * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if modelManager.isInstalled(model.id) {
                    if modelManager.installedTranscriptionModelIDs.count <= 1 {
                        HStack(spacing: 8) {
                            Button("Remove") {
                                modelManager.removeTranscriptionModel(model.id, fallbackDefault: settings.defaultTranscriptionModelID)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(true)
                            .help("You can't remove the last installed model")

                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("You can't remove the last installed model")
                                .onHover { isHovering in
                                    if isHovering {
                                        hoveredLockedModelID = model.id
                                    } else if hoveredLockedModelID == model.id {
                                        hoveredLockedModelID = nil
                                    }
                                }
                                .popover(
                                    isPresented: Binding(
                                        get: { hoveredLockedModelID == model.id },
                                        set: { isPresented in
                                            if !isPresented && hoveredLockedModelID == model.id {
                                                hoveredLockedModelID = nil
                                            }
                                        }
                                    ),
                                    arrowEdge: .trailing
                                ) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Can't remove this model")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("At least one transcription model")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("must remain installed.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                }
                        }
                    } else {
                        Button("Remove") {
                            modelManager.removeTranscriptionModel(model.id, fallbackDefault: settings.defaultTranscriptionModelID)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                } else {
                    Button("Download") {
                        modelManager.downloadTranscriptionModel(model.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(10)
    }

    private func diskInfoLabel(for model: AIModelDescriptor) -> String {
        if modelManager.isInstalled(model.id),
           let bytes = modelManager.cachedInstalledSizeBytes(for: model.id) {
            return "Disk \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        }

        return "Disk ~\(model.sizeLabel)"
    }
}

// MARK: - About

struct AboutSettings: View {
    @State private var planManager = PlanManager.shared
    @EnvironmentObject private var updateChecker: UpdateCheckerService
    @EnvironmentObject private var appDelegate: AppDelegate

    private static let repositoryURL = "https://github.com/ninilich/boring-meeting"
    static let sourceCodeURL = URL(string: repositoryURL)!
    static let issuesURL = URL(string: "\(repositoryURL)/issues")!
    static let privacyPolicyURL = URL(string: "\(repositoryURL)/blob/main/privacy-policy.md")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var updateStatusText: String? {
        switch updateChecker.manualCheckState {
        case .idle:
            return nil
        case .checking:
            return "Checking App Store..."
        case .upToDate:
            return "You're up to date."
        case .updateAvailable(let latest):
            return "Update available: \(latest)."
        case .failed(let reason):
            return "Couldn't check updates: \(reason)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ZStack {
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.18), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                    .frame(width: 160, height: 160)

                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                }

                Text("BoringMeeting")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("BoringMeeting — \(planManager.currentTier.marketingDescriptor).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Updates")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Spacer()

                        Button("Check for updates") {
                            Task {
                                await updateChecker.checkForUpdatesManually()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(updateChecker.manualCheckState == .checking)
                    }

                    if let knownVersion = updateChecker.knownUpdateVersion {
                        Text("A new version (\(knownVersion)) is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Open in App Store") {
                            if let url = updateChecker.knownUpdateURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updateChecker.knownUpdateURL == nil)
                    }

                    if let updateStatusText {
                        Text(updateStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Button("Versions history") {
                        appDelegate.openVersionsHistory()
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Open source")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text("BoringMeeting is free and open source (GPL-3.0).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        Link("Source code", destination: AboutSettings.sourceCodeURL)
                        Link("Report an issue", destination: AboutSettings.issuesURL)
                        Link("Privacy policy", destination: AboutSettings.privacyPolicyURL)
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Anonymous usage analytics")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("BoringMeeting sends one anonymous daily usage ping while the app is open. No personal data or recordings are collected, and IP addresses are not stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Uses a truncated, irreversible device hash for daily active device counts only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AIModelManager())
        .environmentObject(UpdateCheckerService())
        .environmentObject(AppDelegate())
}
