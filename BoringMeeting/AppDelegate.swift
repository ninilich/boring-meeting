import SwiftUI
import AppKit
import SwiftData
import Combine
import UserNotifications
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import Heartbeat
import SQLite3

/// Manages menu bar icon and application menu
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    
    // Menu bar icon (top-right corner of macOS)
    var statusItem: NSStatusItem?
    
    // Audio capture manager
    var audioCaptureManager: AudioCaptureManager?
    
    // Recording state
    @Published var isRecording = false
    var recordingTimer: Timer?
    var recordingStartTime: Date?
    @Published var recordingDuration: TimeInterval = 0
    @Published var isFinalizingRecording = false
    @Published var showRecordingInterruptedAlert = false
    @Published var recordingInterruptedMessage = ""
    private var isStoppingRecording = false

    // Permissions state
    @Published var microphoneAuthorized = false
    @Published var screenCaptureAuthorized = false
    
    // SwiftData container
    let modelContainer: ModelContainer
    let aiModelManager: AIModelManager
    let transcriptionManager: TranscriptionManager
    let updateChecker: UpdateCheckerService
    let whatsNewService: WhatsNewService
    let cliAPIServer: CLIAPIServer
    private var storeWasRecovered: Bool
    @Published var suppressWhatsNewForCurrentVersion = false
    private var cancellables: Set<AnyCancellable> = []
    private var cleanupTimer: Timer?

    override init() {
        let schema = Schema([Meeting.self])
        let appSupportURL = URL.applicationSupportDirectory
        let boringMeetingDir = appSupportURL.appending(path: "BoringMeeting")
        try? FileManager.default.createDirectory(at: boringMeetingDir, withIntermediateDirectories: true)
        let storeURL = boringMeetingDir.appending(path: "default.store", directoryHint: .notDirectory)
        let legacyURL = appSupportURL.appending(path: "default.store", directoryHint: .notDirectory)
        if !FileManager.default.fileExists(atPath: storeURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path),
           AppDelegate.isMeetingStore(at: legacyURL) {
            try? FileManager.default.moveItem(at: legacyURL, to: storeURL)
            for suffix in ["-shm", "-wal"] {
                let src = appSupportURL.appending(path: "default.store\(suffix)", directoryHint: .notDirectory)
                let dst = boringMeetingDir.appending(path: "default.store\(suffix)", directoryHint: .notDirectory)
                try? FileManager.default.moveItem(at: src, to: dst)
            }
        }
        let (container, recovered) = AppDelegate.openOrRecoverStore(schema: schema, at: storeURL)
        modelContainer = container
        storeWasRecovered = recovered
        aiModelManager = AIModelManager()
        transcriptionManager = TranscriptionManager(modelContainer: modelContainer, modelManager: aiModelManager)
        updateChecker = UpdateCheckerService()
        whatsNewService = WhatsNewService()
        cliAPIServer = CLIAPIServer(modelContainer: modelContainer, transcriptionManager: transcriptionManager)
        print("✅ SwiftData initialized\(recovered ? " (recovered from corrupted store)" : "")")
        super.init()
    }
    
    // Main recordings window
    var recordingsWindow: NSWindow?
    
    // Settings window
    var settingsWindow: NSWindow?

    // What's New window
    var whatsNewWindow: NSWindow?

    // Versions history window
    var versionsHistoryWindow: NSWindow?
    
    /// Called when app launches
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // Initialize audio capture manager
        audioCaptureManager = AudioCaptureManager()
        audioCaptureManager?.onSourceDropoutDetected = { [weak self] reason in
            Task { @MainActor in
                self?.handleAudioSourceDropout(reason: reason)
            }
        }
        
        // Create menu bar icon based on persisted setting
        syncMenuBarIconVisibility()

        AppSettings.shared.$hideMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncMenuBarIconVisibility()
            }
            .store(in: &cancellables)

        configureSystemHelpMenuItem()

        // Request local notification permission for completion notifications
        requestNotificationPermissionIfNeeded()

        // Initialize permissions state for UI
        refreshPermissionStatus()
        
        // Don't request permissions on launch - let them be requested naturally on first recording
        // This avoids hanging when user clicks "Reopen" after granting Screen Recording permission

        // Reset any meetings stuck in "in progress" from a previous interrupted session
        transcriptionManager.recoverInterruptedTranscriptions()

        // Recover transcriptions interrupted by system sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // One-time migration: seed speed factor statistics from existing completed meetings
        migrateTranscriptionSpeedFactorsIfNeeded()

        // Auto-delete old recordings if configured
        cleanupOldMeetingsIfNeeded()
        scheduleCleanupTimer()

        // Start CLI API server if enabled
        syncCLIAPIServer()
        AppSettings.shared.$cliAPIEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncCLIAPIServer() }
            .store(in: &cancellables)
        AppSettings.shared.$cliAPIPort
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncCLIAPIServer() }
            .store(in: &cancellables)

        // Start device tracking for analytics
        Heartbeat.start()

        updateChecker.$knownUpdate
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateChecker.checkForUpdatesIfNeeded(
                automaticChecksEnabled: AppSettings.shared.updatesCheckEnabled,
                intervalDays: AppSettings.updateCheckIntervalDays
            )
            self.updateMenu()
            self.presentWhatsNewIfNeeded()
        }

        // Enforce a hard minimum size for the main recordings window.
        // SwiftUI frame(minWidth/minHeight) is only a layout hint, not an NSWindow constraint.
        DispatchQueue.main.async {
            NSApplication.shared.windows
                .first(where: { $0.styleMask.contains(.resizable) })?
                .minSize = NSSize(width: 920, height: 500)
        }

        if storeWasRecovered {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Database Recovered"
                alert.informativeText = "The meetings database was corrupted and could not be opened. A new empty database has been created.\n\nYour audio recordings are still on disk — only the database entries were lost. A backup of the corrupted database was saved in Application Support/BoringMeeting/."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func configureSystemHelpMenuItem() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let helpMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Help" })?.submenu else { return }
            guard let helpItem = helpMenu.items.first(where: { $0.title == "BoringMeeting Help" }) else { return }

            helpItem.target = self
            helpItem.action = #selector(openAboutFromSystemHelp)
        }
    }
    
    /// Setup dropdown menu
    private func setupMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        
        // Recording button (changes based on state)
        let recordItem = NSMenuItem(
            title: isRecording ? "● Stop Recording" : "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        recordItem.tag = 100 // Tag to find and update later
        
        // Set icon for menu item
        if !isRecording {
            recordItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        } else {
            recordItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
        }
        
        menu.addItem(recordItem)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.tag = 200
        settingsItem.image = settingsMenuImage(showBadge: updateChecker.hasKnownUpdate)
        menu.addItem(settingsItem)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Quit button
        let quitItem = NSMenuItem(
            title: "Quit BoringMeeting",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "BoringMeeting")?.withSymbolConfiguration(config)
        }

        setupMenu()
        updateMenuBarIcon()
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func syncCLIAPIServer() {
        let settings = AppSettings.shared
        if settings.cliAPIEnabled {
            cliAPIServer.start(on: settings.cliAPIPort)
        } else {
            cliAPIServer.stop()
        }
    }

    private func syncMenuBarIconVisibility() {
        let hideMenuBarIcon = AppSettings.shared.hideMenuBarIcon

        if hideMenuBarIcon {
            if isRecording || isFinalizingRecording {
                ensureStatusItem()
                updateMenu()
                return
            }
            removeStatusItem()
            return
        }

        ensureStatusItem()
        updateMenu()
    }
    
    /// Toggle recording on/off
    @objc func toggleRecording() {
        guard !isFinalizingRecording else { return }

        if isRecording {
            isRecording = false
            stopRecording()
            updateMenu()
        } else {
            startRecordingFromUI()
        }
    }

    /// Start recording from SwiftUI actions (toolbar/commands)
    func startRecordingFromUI() {
        guard !isRecording, !isFinalizingRecording else { return }

        print("▶️ UI requested recording start")

        if ensurePermissionGateConfirmed() {
            isRecording = true
            startRecording()
            updateMenu()
        } else {
            print("⛔️ Recording start blocked by permission gate")
        }
    }

    /// Stop recording from SwiftUI actions (toolbar/main screen)
    func stopRecordingFromUI() {
        guard isRecording, !isFinalizingRecording else { return }
        isRecording = false
        stopRecording()
        updateMenu()
    }

    /// Toggle recording from SwiftUI actions
    func toggleRecordingFromUI() {
        if isRecording {
            stopRecordingFromUI()
        } else {
            startRecordingFromUI()
        }
    }

    var allPermissionsGranted: Bool {
        microphoneAuthorized && screenCaptureAuthorized
    }

    func refreshPermissionStatus() {
        microphoneAuthorized = isMicrophoneAuthorized()
        screenCaptureAuthorized = isScreenCaptureAuthorized()
    }

    func requestPermissionsFromUI() {
        requestPermissionsIfNeeded()
        refreshPermissionStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            Task { @MainActor in
                self?.refreshPermissionStatus()
            }
        }
    }

    func openPermissionSettingsFromUI() {
        openPermissionSettings()
    }
    
    /// Start recording
    private func startRecording() {
        print("🔴 Recording started")
        recordingStartTime = Date()
        recordingDuration = 0
        
        // Start timer to update duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRecordingDuration()
            }
        }
        
        // Start audio recording
        Task { @MainActor in
            guard let audioCaptureManager = self.audioCaptureManager else { return }
            
            do {
                // Start recording - system will automatically show permission dialogs if needed
                try await audioCaptureManager.startRecording()
                print("✅ Audio recording started successfully")
                
            } catch {
                print("❌ Failed to start recording: \(error.localizedDescription)")
                
                // Don't show any error dialogs - let the system handle permission prompts
                // Just reset the recording state
                self.isRecording = false
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.updateMenu()
            }
        }
    }
    
    /// Stop recording
    private func stopRecording() {
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        isFinalizingRecording = true

        print("⏹ Recording stopped - Duration: \(formatDuration(recordingDuration))")
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop audio recording
        guard let audioCaptureManager = audioCaptureManager else {
            isStoppingRecording = false
            isFinalizingRecording = false
            return
        }
        
        Task { @MainActor in
            defer {
                self.isStoppingRecording = false
                self.isFinalizingRecording = false
                self.updateMenu()
                self.syncMenuBarIconVisibility()
            }

            guard let recordingURL = await audioCaptureManager.stopRecording() else {
                print("❌ Failed to get recording URL")
                return
            }
            
            // Save recording to database
            self.saveMeeting(audioURL: recordingURL, duration: self.recordingDuration)
            
            print("✅ Recording saved successfully")

            // Show notification
            self.deliverRecordingCompletedNotification()
        }
    }

    private func handleAudioSourceDropout(reason: String) {
        guard isRecording else { return }

        print("⚠️ Stopping recording after source dropout: \(reason)")

        updateRecordingDuration()
        isRecording = false

        if reason.hasPrefix("write-error:") {
            recordingInterruptedMessage = "Recording was stopped because audio could not be written to disk. Your storage may be full or the file system is unavailable."
        } else {
            recordingInterruptedMessage = "Audio device or microphone change was detected. This is not supported during recording, so recording has been stopped."
        }
        showRecordingInterruptedAlert = true

        stopRecording()
        updateMenu()
    }
    
    /// Save meeting to database
    private func saveMeeting(audioURL: URL, duration: TimeInterval) {
        let modelContext = modelContainer.mainContext
        
        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
        
        // Create relative path from storage root for reliable reopen/delete
        let relativePath = makeRelativeAudioPath(from: audioURL)
        
        // Create meeting object
        let settings = AppSettings.shared
        let meeting = Meeting(
            date: recordingStartTime ?? Date(),
            duration: duration,
            audioFilePath: relativePath,
            title: settings.generateRecordingTitle(for: recordingStartTime ?? Date())
        )
        meeting.fileSize = fileSize
        
        // Insert into database
        modelContext.insert(meeting)
        
        do {
            try modelContext.save()
            print("✅ Meeting saved to database: \(meeting.title)")
        } catch {
            print("❌ Failed to save meeting: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Failed to Save Meeting"
            alert.informativeText = "The recording was saved to disk but could not be added to the database.\n\nError: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    /// Update recording duration and menu
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
        updateMenu()
    }
    
    /// Update menu items based on current state
    private func updateMenu() {
        guard let menu = statusItem?.menu else { return }
        
        // Find and update recording button
        if let recordItem = menu.item(withTag: 100) {
            if isRecording {
                let duration = formatDuration(recordingDuration)
                recordItem.title = "● Stop Recording \(duration)"
                recordItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            } else if isFinalizingRecording {
                recordItem.title = "Finishing Recording…"
                recordItem.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
            } else {
                recordItem.title = "Start Recording"
                recordItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
            }
        }

        if let settingsItem = menu.item(withTag: 200) {
            settingsItem.image = settingsMenuImage(showBadge: updateChecker.hasKnownUpdate)
        }
        
        // Update menu bar icon to show recording state
        updateMenuBarIcon()
    }
    
    /// Update menu bar icon based on recording state
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        guard let base = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "BoringMeeting")?
            .withSymbolConfiguration(config) else { return }

        if isRecording {
            button.image = menuBarIconWithDot(base: base)
            button.contentTintColor = nil
        } else {
            button.image = base
            button.contentTintColor = nil
        }
    }

    private func menuBarIconWithDot(base: NSImage) -> NSImage {
        let dotDiameter: CGFloat = 5
        let padding: CGFloat = 2
        let totalWidth = base.size.width + dotDiameter + padding
        let totalHeight = base.size.height

        let result = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: base.size))

            let dotX = base.size.width + padding - 1
            let dotY = totalHeight - dotDiameter  // top-right corner
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)).fill()
            return true
        }
        result.isTemplate = false
        return result
    }

    private func settingsMenuImage(showBadge: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let base = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return nil
        }

        guard showBadge else {
            return base
        }

        let dotDiameter: CGFloat = 5
        let result = NSImage(size: base.size, flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: base.size))

            let dotX = max(base.size.width - dotDiameter - 1, 0)
            let dotY = max(base.size.height - dotDiameter - 1, 0)

            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)).fill()
            return true
        }
        result.isTemplate = false
        return result
    }
    
    /// Format duration as MM:SS
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Open settings window
    @objc func openSettings() {
        openSettingsWindow(tab: updateChecker.hasKnownUpdate ? .about : .general)
    }

    @objc private func openAboutFromSystemHelp() {
        openSettingsWindow(tab: .about)
    }

    private func makeSettingsRootView(tab: SettingsTab) -> AnyView {
        AnyView(
            SettingsView(initialTab: tab)
                .environmentObject(aiModelManager)
                .environmentObject(updateChecker)
                .environmentObject(self)
        )
    }

    private func presentWhatsNewIfNeeded() {
        guard whatsNewService.shouldShowOnLaunch(settings: .shared) else { return }
        presentWhatsNew(force: false)
    }

    func presentWhatsNew(force: Bool) {
        guard let release = whatsNewService.currentReleaseNote() else { return }

        if !force && !whatsNewService.shouldShowOnLaunch(settings: .shared) {
            return
        }

        suppressWhatsNewForCurrentVersion = whatsNewService.isSuppressedForCurrentVersion(settings: .shared)
        whatsNewService.markSeen(release.version, settings: .shared)
        openWhatsNewWindow(for: release)
    }

    func dismissWhatsNew(savePreference: Bool = true) {
        if savePreference {
            whatsNewService.setSuppressedForCurrentVersion(suppressWhatsNewForCurrentVersion, settings: .shared)
        }
        whatsNewWindow?.close()
    }

    func openVersionsHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let historyView = AnyView(VersionsHistoryView(releases: whatsNewService.allReleaseNotes()))

        if let window = versionsHistoryWindow {
            if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = historyView
            } else {
                window.contentViewController = NSHostingController(rootView: historyView)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: historyView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Versions history"
        window.setContentSize(NSSize(width: 640, height: 520))
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        versionsHistoryWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func openWhatsNewWindow(for release: WhatsNewService.ReleaseNote) {
        NSApp.activate(ignoringOtherApps: true)

        let content = AnyView(
            WhatsNewWindowContent(
                appDelegate: self,
                release: release,
                onContinue: { [weak self] in
                    self?.dismissWhatsNew(savePreference: true)
                }
            )
        )

        if let window = whatsNewWindow {
            if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = content
            } else {
                window.contentViewController = NSHostingController(rootView: content)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "What's New"
        window.setContentSize(NSSize(width: 560, height: 420))
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        whatsNewWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func openSettingsWindow(tab: SettingsTab) {
        NSApp.activate(ignoringOtherApps: true)
        let settingsView = makeSettingsRootView(tab: tab)
        
        // If window exists, just show it
        if let window = settingsWindow {
            if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = settingsView
            } else {
                window.contentViewController = NSHostingController(rootView: settingsView)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // Create new settings window
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 500, height: 400))
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else {
            return
        }

        if closingWindow === settingsWindow {
            updateChecker.resetManualCheckState()
            return
        }

        if closingWindow === whatsNewWindow {
            // Closing via window controls should not change persisted preference.
            suppressWhatsNewForCurrentVersion = whatsNewService.isSuppressedForCurrentVersion(settings: .shared)
            return
        }
    }
    
    /// Handle application termination
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if recording is in progress
        if isRecording {
            let alert = NSAlert()
            alert.messageText = "Recording in progress"
            alert.informativeText = "Stop recording and quit?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Stop & Quit")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Stop recording and quit
                stopRecording()
                return .terminateNow
            } else {
                // Cancel quit
                return .terminateCancel
            }
        }
        
        return .terminateNow
    }

    @objc private func handleSystemWake() {
        transcriptionManager.recoverSleepInterruptedTranscriptions()
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func ensurePermissionGateConfirmed() -> Bool {
        refreshPermissionStatus()

        if allPermissionsGranted {
            return true
        }

        // Non-blocking permission flow to avoid UI hangs:
        // request what we can immediately and let user complete the rest via permissions panel.
        requestPermissionsIfNeeded()
        refreshPermissionStatus()

        if allPermissionsGranted {
            return true
        }

        print("⚠️ Permissions are not fully granted. Use Request / Open Settings / Refresh in the permissions panel.")
        return false
    }

    private func isMicrophoneAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func isScreenCaptureAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func openPermissionSettings() {
        if let screenURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(screenURL)
        }
        if let micURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(micURL)
        }
    }

    private func requestPermissionsIfNeeded() {
        if !isMicrophoneAuthorized() {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshPermissionStatus()
                }
            }
        }

        if !isScreenCaptureAuthorized() {
            Task {
                if #available(macOS 14.0, *) {
                    _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                } else {
                    _ = try? await SCShareableContent.current
                }
                await MainActor.run { self.refreshPermissionStatus() }
            }
        }

        refreshPermissionStatus()
    }

    private func deliverRecordingCompletedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Recording Complete"
        content.body = "Duration: \(formatDuration(recordingDuration))"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldMeetingsIfNeeded()
            }
        }
    }

    private func cleanupOldMeetingsIfNeeded() {
        let settings = AppSettings.shared
        let days = settings.autoDeleteAfterDays
        guard days > 0 else { return }

        if let last = settings.lastMeetingCleanupDate,
           Date().timeIntervalSince(last) < 86400 { return }

        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }

        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.date < cutoff }
        )
        descriptor.fetchLimit = 500

        guard let meetings = try? modelContainer.mainContext.fetch(descriptor) else { return }

        for meeting in meetings {
            deleteMeetingFilesFromDisk(meeting)
            modelContainer.mainContext.delete(meeting)
        }

        if !meetings.isEmpty {
            try? modelContainer.mainContext.save()
        }

        settings.lastMeetingCleanupDate = Date()
    }

    private func deleteMeetingFilesFromDisk(_ meeting: Meeting) {
        guard let audioURL = meeting.fullAudioPath else { return }
        let parentDirectory = audioURL.deletingLastPathComponent()
        let parentName = parentDirectory.lastPathComponent
        Task.detached {
            let fm = FileManager.default
            if parentName.hasPrefix("recording_") {
                if fm.fileExists(atPath: parentDirectory.path) {
                    try? fm.removeItem(at: parentDirectory)
                }
            } else if fm.fileExists(atPath: audioURL.path) {
                try? fm.removeItem(at: audioURL)
            }
        }
    }

    private func migrateTranscriptionSpeedFactorsIfNeeded() {
        let settings = AppSettings.shared
        guard !settings.isSpeedFactorsMigrated else { return }

        // Organic data already exists — historical migration is no longer relevant.
        if settings.hasAnySpeedFactorData {
            settings.isSpeedFactorsMigrated = true
            return
        }

        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.transcriptionStatus == "completed" }
        )
        descriptor.sortBy = [SortDescriptor(\.date, order: .forward)]

        // If fetch fails, do not mark migration as done — retry on next launch.
        guard let meetings = try? modelContainer.mainContext.fetch(descriptor) else { return }

        for meeting in meetings {
            guard let modelID = meeting.transcriptionModelUsedID,
                  let transcriptionDuration = meeting.transcriptionDuration,
                  meeting.duration >= 600 else { continue }
            settings.updateSpeedFactor(
                modelID: modelID,
                audioDuration: meeting.duration,
                transcriptionDuration: transcriptionDuration
            )
        }

        settings.isSpeedFactorsMigrated = true
    }

    private static func openOrRecoverStore(schema: Schema, at url: URL) -> (ModelContainer, Bool) {
        let config = ModelConfiguration(schema: schema, url: url)
        if let container = try? ModelContainer(for: schema, migrationPlan: MeetingMigrationPlan.self, configurations: [config]) {
            return (container, false)
        }
        print("⚠️ SwiftData store open failed, attempting recovery...")
        let timestamp = String(Int(Date().timeIntervalSince1970))
        for suffix in ["", "-shm", "-wal"] {
            let src = url.deletingLastPathComponent()
                .appending(path: "default.store\(suffix)", directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = url.deletingLastPathComponent()
                .appending(path: "default.store\(suffix).corrupt_\(timestamp)", directoryHint: .notDirectory)
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                // Backup failed (e.g. disk full) — delete the corrupt file so the
                // fresh ModelContainer can create a clean one at the same path.
                print("⚠️ Could not backup corrupt store\(suffix) (\(error)), removing")
                try? FileManager.default.removeItem(at: src)
            }
        }
        do {
            let freshConfig = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, migrationPlan: MeetingMigrationPlan.self, configurations: [freshConfig])
            print("✅ SwiftData store recovered, corrupted backup retained")
            return (container, true)
        } catch {
            fatalError("SwiftData recovery failed: \(error)")
        }
    }

    private static func isMeetingStore(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='ZMEETING'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func makeRelativeAudioPath(from audioURL: URL) -> String {
        let storageURL = AppSettings.recordingsRootURL.standardizedFileURL
        let fileURL = audioURL.standardizedFileURL

        let storagePrefix = storageURL.path.hasSuffix("/") ? storageURL.path : storageURL.path + "/"
        if fileURL.path.hasPrefix(storagePrefix) {
            return String(fileURL.path.dropFirst(storagePrefix.count))
        }

        return fileURL.lastPathComponent
    }
}

private struct WhatsNewWindowContent: View {
    @ObservedObject var appDelegate: AppDelegate
    let release: WhatsNewService.ReleaseNote
    let onContinue: () -> Void

    var body: some View {
        WhatsNewSheet(
            release: release,
            dontShowAgain: $appDelegate.suppressWhatsNewForCurrentVersion,
            onContinue: onContinue
        )
    }
}
