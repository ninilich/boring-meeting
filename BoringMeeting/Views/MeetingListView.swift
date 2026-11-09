import SwiftUI
import SwiftData
import StoreKit

/// Main view showing list of all recorded meetings
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appDelegate: AppDelegate
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @State private var planManager = PlanManager.shared
    
    @State private var selectedMeetingIDs: Set<UUID> = []
    @State private var showDeleteAlert = false
    @State private var pendingDeleteIDs: Set<UUID> = []
    @State private var showRenameAlert = false
    @State private var meetingToRename: Meeting?
    @State private var newName = ""
    @State private var permissionsRequested = false
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var transcriptionManager: TranscriptionManager
    @EnvironmentObject private var modelManager: AIModelManager
    @State private var batchModelID = AppSettings.shared.defaultTranscriptionModelID
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationSplitView {
            // Sidebar - List of recordings
            sidebarContent
                .navigationSplitViewColumnWidth(min: 280, ideal: 280)
        } detail: {
            // Detail view - Selected recording
            if selectedMeetingIDs.count > 1 {
                multiSelectionDetailView
            } else if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting, isRecording: appDelegate.isRecording)
            } else {
                detailWelcomeView
            }
        }
        .alert(deleteAlertTitle, isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteMeetings(withIDs: pendingDeleteIDs)
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .alert("Rename Recording", isPresented: $showRenameAlert) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let meeting = meetingToRename, !newName.isEmpty {
                    renameMeeting(meeting, to: newName)
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Enter a new name for this recording")
        }
        .alert("Recording Stopped", isPresented: $appDelegate.showRecordingInterruptedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appDelegate.recordingInterruptedMessage)
        }
        .onAppear {
            appDelegate.refreshPermissionStatus()
        }
        .onDeleteCommand {
            requestDelete(ids: selectedMeetingIDs)
        }
        .onKeyPress(.escape, phases: .down) { _ in
            guard !selectedMeetingIDs.isEmpty else { return .ignored }
            selectedMeetingIDs = []
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "\r\u{0003}"), phases: .down) { _ in
            guard let meeting = selectedMeeting else { return .ignored }
            meetingToRename = meeting
            newName = meeting.title
            showRenameAlert = true
            return .handled
        }
        .onChange(of: meetings.map(\.id)) { _, currentIDs in
            selectedMeetingIDs = selectedMeetingIDs.intersection(Set(currentIDs))
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestAppReview)) { _ in
            requestReview()
        }
    }
    
    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            if settings.recordingPanelPosition == .top {
                controlsBlock
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                Divider()
                meetingsList
            } else {
                meetingsList
                Divider()
                controlsBlock
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Recordings")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appDelegate.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Open Settings")
            }
        }
        .frame(minWidth: 290, maxHeight: .infinity, alignment: .top)
    }

    private var controlsBlock: some View {
        VStack(spacing: 10) {
            recordingPanel

            if !appDelegate.allPermissionsGranted {
                permissionsPanel
            }
        }
        .padding(.horizontal, 10)
    }

    private var meetingsList: some View {
        let queuedIDs = Set(transcriptionManager.batchQueue)
        return Group {
            if meetings.isEmpty {
                emptyDetailView
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selectedMeetingIDs) {
                        ForEach(meetings) { meeting in
                            MeetingRow(meeting: meeting, isQueued: queuedIDs.contains(meeting.id))
                                .id(meeting.id)
                                .tag(meeting.id)
                                .contextMenu {
                                    contextMenuButtons(for: meeting)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        requestDelete(ids: [meeting.id])
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: meetings.first?.id) { _, newTopID in
                        guard let newTopID else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newTopID, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var recordingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            recordingActionButton(title: recordingActionTitle, maxWidth: .infinity)

            if appDelegate.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording \(formatDuration(appDelegate.recordingDuration))")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.red)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange.opacity(0.85))

                    Text("Do not switch microphone, headphones, or audio output during recording — this may stop recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else if appDelegate.isFinalizingRecording {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finishing recording…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Ready to record")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Permissions required")
            }
                .font(.headline)

            permissionRow(
                title: "Microphone",
                granted: appDelegate.microphoneAuthorized
            )

            permissionRow(
                title: "Screen Recording",
                granted: appDelegate.screenCaptureAuthorized
            )

            HStack(spacing: 8) {
                Button("Continue") {
                    permissionsRequested = true
                    appDelegate.requestPermissionsFromUI()
                }
                .buttonStyle(.borderedProminent)
                .frame(width: 76)
                Button("Open Settings") {
                    appDelegate.openPermissionSettingsFromUI()
                }
                .buttonStyle(.bordered)
                .frame(width: 110)
                .opacity(permissionsRequested ? 1 : 0)
                .allowsHitTesting(permissionsRequested)
                Button("Check") {
                    appDelegate.refreshPermissionStatus()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                .frame(width: 58)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var idleRecordingGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 120/255, green: 220/255, blue: 148/255),
                     Color(red: 72/255, green: 180/255, blue: 100/255)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var activeRecordingGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 235/255, green: 88/255, blue: 88/255),
                     Color(red: 195/255, green: 48/255, blue: 48/255)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var finalizingRecordingGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 180/255, green: 180/255, blue: 180/255),
                     Color(red: 140/255, green: 140/255, blue: 140/255)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var recordingActionTitle: String {
        if appDelegate.isFinalizingRecording {
            return "Finishing Recording..."
        }
        return appDelegate.isRecording ? "Stop Recording" : "Start New Recording"
    }

    private var recordingActionGradient: LinearGradient {
        if appDelegate.isFinalizingRecording {
            return finalizingRecordingGradient
        }
        return appDelegate.isRecording ? activeRecordingGradient : idleRecordingGradient
    }

    private var recordingActionIcon: String {
        if appDelegate.isFinalizingRecording {
            return "hourglass"
        }
        return appDelegate.isRecording ? "stop.fill" : "mic.fill"
    }

    private func recordingActionButton(title: String, maxWidth: CGFloat?) -> some View {
        Button {
            appDelegate.toggleRecordingFromUI()
        } label: {
            Label(title, systemImage: recordingActionIcon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: maxWidth)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(recordingActionGradient)
                )
        }
        .buttonStyle(.plain)
        .disabled(appDelegate.isFinalizingRecording)
        .opacity(appDelegate.isFinalizingRecording ? 0.9 : 1)
    }

    private func permissionRow(title: String, granted: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(granted ? "Granted" : "Missing")
                .foregroundStyle(granted ? .green : .red)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
    
    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(onboardingSteps, id: \.title) { step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(step.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: step.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(step.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct OnboardingStep {
        let icon: String
        let color: Color
        let title: String
        let description: String
    }

    private let onboardingSteps: [OnboardingStep] = [
        OnboardingStep(
            icon: "mic.fill",
            color: .red,
            title: "Record",
            description: "Capture any meeting privately on your Mac"
        ),
        OnboardingStep(
            icon: "waveform",
            color: .blue,
            title: "Transcribe",
            description: "Local AI — no data leaves your device"
        ),
        OnboardingStep(
            icon: "doc.text",
            color: .green,
            title: "Read & Copy",
            description: "Full transcript ready in minutes"
        )
    ]

    private var detailWelcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                ForEach(onboardingSteps, id: \.title) { step in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(step.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: step.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(step.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(step.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(width: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyDetailView: some View {
        VStack(spacing: 8) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }
            Text("BoringMeeting")
                .font(.title2)
                .fontWeight(.bold)
            Text("your private meeting transcriber")
                .font(.body)
                .italic()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var multiSelectionDetailView: some View {
        let selectedCount = selectedMeetings.count
        let totalDuration = selectedMeetings.reduce(0) { $0 + $1.duration }
        let totalSize = selectedMeetings.reduce(Int64(0)) { $0 + $1.fileSize }
        let eligibleMeetings = selectedMeetings.filter { $0.status == .notStarted || $0.status == .failed }
        let eligibleDuration = eligibleMeetings.reduce(0.0) { $0 + $1.duration }

        return VStack(spacing: 18) {
            ContentUnavailableView {
                Label("Multiple Recordings Selected", systemImage: "checklist")
            } description: {
                Text("Selected: \(selectedCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Total duration: \(formatDuration(totalDuration))")
                Text("Total size: \(formatFileSize(totalSize))")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !transcriptionManager.batchQueue.isEmpty {
                VStack(spacing: 10) {
                    Text("Transcribing \(transcriptionManager.batchCompleted + 1) of \(transcriptionManager.batchTotal)...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let currentID = transcriptionManager.batchQueue.first {
                        ProgressView(value: transcriptionManager.progress(for: currentID))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 240)
                            .accessibilityLabel("Transcription progress for current meeting")
                    }
                    Button("Cancel Queue") {
                        transcriptionManager.cancelBatch()
                    }
                    .buttonStyle(.bordered)
                }
            } else if !eligibleMeetings.isEmpty {
                let count = eligibleMeetings.count
                let installedModels = modelManager.transcriptionModels.filter { modelManager.isInstalled($0.id) }
                let notInstalledModels = modelManager.transcriptionModels.filter { !modelManager.isInstalled($0.id) }
                VStack(spacing: 12) {
                    if installedModels.isEmpty {
                        HStack(spacing: 4) {
                            Text("No models installed.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                appDelegate.openSettingsWindow(tab: .transcription)
                            }
                            .font(.callout)
                        }
                    } else {
                        Picker("Model", selection: $batchModelID) {
                            ForEach(installedModels) { model in
                                Text(batchModelPickerTitle(for: model)).tag(model.id)
                            }
                            if !notInstalledModels.isEmpty {
                                Section("Not installed") {
                                    ForEach(notInstalledModels) { model in
                                        Text(batchModelPickerTitle(for: model)).tag(model.id)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 320)

                        HStack(spacing: 4) {
                            Text("Language:")
                                .foregroundStyle(.secondary)
                            if let locked = modelManager.lockedLanguage(for: batchModelID) {
                                Label(locked.displayName, systemImage: "lock.fill")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(settings.transcriptionLanguage.displayName)
                            }
                        }
                        .font(.callout)

                        if let descriptor = modelManager.descriptor(for: batchModelID),
                           let resolved = AppSettings.shared.resolvedSpeedFactor(for: batchModelID, catalogFactor: descriptor.catalogSpeedFactor),
                           resolved.factor > 0,
                           eligibleDuration > 0 {
                            Text("Estimated time: ~\(formatTranscriptionDuration(eligibleDuration / resolved.factor))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Button("Transcribe \(count) \(count == 1 ? "Meeting" : "Meetings")") {
                            transcriptionManager.enqueueTranscriptions(for: eligibleMeetings, modelID: batchModelID)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!modelManager.isInstalled(batchModelID))
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Delete Selected", role: .destructive) {
                    requestDelete(ids: selectedMeetingIDs)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button("Clear Selection") {
                    selectedMeetingIDs.removeAll()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            clampBatchModelID()
        }
        .onChange(of: modelManager.transcriptionModels.map(\.id)) {
            clampBatchModelID()
        }
    }

    private func clampBatchModelID() {
        guard !modelManager.transcriptionModels.contains(where: { $0.id == batchModelID }) else { return }
        if let first = modelManager.transcriptionModels.first(where: { modelManager.isInstalled($0.id) })?.id
            ?? modelManager.transcriptionModels.first?.id {
            batchModelID = first
        }
    }

    // MARK: - Context Menu
    
    @ViewBuilder
    private func contextMenuButtons(for meeting: Meeting) -> some View {
        Button {
            playRecording(meeting)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        
        Button {
            meetingToRename = meeting
            newName = meeting.title
            showRenameAlert = true
        } label: {
            Label("Rename...", systemImage: "pencil")
        }
        
        Divider()
        
        Button(role: .destructive) {
            requestDelete(ids: [meeting.id])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Actions
    
    private func newRecording() {
        appDelegate.startRecordingFromUI()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatTranscriptionDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }

    private func batchModelPickerTitle(for model: AIModelDescriptor) -> String {
        let speedText: String
        if let resolved = AppSettings.shared.resolvedSpeedFactor(for: model.id, catalogFactor: model.catalogSpeedFactor) {
            let label = "~\(Int(resolved.factor.rounded()))x"
            speedText = resolved.isMeasured ? label : "\(label)*"
        } else {
            speedText = "\(model.speedLabel)*"
        }
        let langSuffix = model.lockedLanguage.map { ", \($0.uppercased()) only" } ?? ""
        return "\(model.displayName) (\(model.qualityLabel), \(speedText)\(langSuffix))"
    }

    private func playRecording(_ meeting: Meeting) {
        selectedMeetingIDs = [meeting.id]
        // Audio player will auto-play when detail view appears
    }
    
    private func saveContext() {
        do { try modelContext.save() }
        catch { print("⚠️ save failed: \(error.localizedDescription)") }
    }

    private func renameMeeting(_ meeting: Meeting, to newName: String) {
        meeting.title = newName
        saveContext()
    }
    
    private func deleteMeetings(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let targets = meetings.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        if !Set(transcriptionManager.batchQueue).isDisjoint(with: ids) {
            transcriptionManager.cancelBatch()
        }

        for meeting in targets {
            deleteMeetingFilesFromDisk(meeting)
            modelContext.delete(meeting)
        }

        selectedMeetingIDs.subtract(ids)
        pendingDeleteIDs.removeAll()
        saveContext()
    }

    private func requestDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
        showDeleteAlert = true
    }

    private var selectedMeeting: Meeting? {
        guard selectedMeetingIDs.count == 1,
              let id = selectedMeetingIDs.first else {
            return nil
        }
        return meetings.first(where: { $0.id == id })
    }

    private var selectedMeetings: [Meeting] {
        meetings.filter { selectedMeetingIDs.contains($0.id) }
    }

    private var deleteAlertTitle: String {
        pendingDeleteIDs.count > 1 ? "Delete Selected Recordings?" : "Delete Recording?"
    }

    private var deleteAlertMessage: String {
        if pendingDeleteIDs.count > 1 {
            return "This cannot be undone. \(pendingDeleteIDs.count) recordings and all related files on disk will be permanently deleted."
        }
        return "This cannot be undone. The recording and all related files on disk will be permanently deleted."
    }

    private func deleteMeetingFilesFromDisk(_ meeting: Meeting) {
        guard let audioURL = meeting.fullAudioPath else { return }

        let parentDirectory = audioURL.deletingLastPathComponent()
        let parentName = parentDirectory.lastPathComponent

        Task.detached {
            let fileManager = FileManager.default
            if parentName.hasPrefix("recording_") {
                if fileManager.fileExists(atPath: parentDirectory.path) {
                    try? fileManager.removeItem(at: parentDirectory)
                }
            } else if fileManager.fileExists(atPath: audioURL.path) {
                try? fileManager.removeItem(at: audioURL)
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.1f KB", kb)
        }
    }
}


#Preview {
    let container = try! ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let appDelegate = AppDelegate()
    
    // Add sample meetings
    let meeting1 = Meeting(
        date: Date(),
        duration: 1845,
        audioFilePath: "test1.m4a",
        title: "Recording 11.02.2026 11:30"
    )
    meeting1.fileSize = 5_242_880
    meeting1.status = .completed
    meeting1.transcript = "[Speaker 1, 00:15] Welcome to the meeting"
    
    let meeting2 = Meeting(
        date: Date().addingTimeInterval(-86400),
        duration: 525,
        audioFilePath: "test2.m4a",
        title: "Recording 10.02.2026 09:15"
    )
    meeting2.fileSize = 2_100_000
    meeting2.status = .notStarted
    
    container.mainContext.insert(meeting1)
    container.mainContext.insert(meeting2)
    
    return MeetingListView()
        .modelContainer(container)
        .environmentObject(appDelegate)
        .environmentObject(appDelegate.aiModelManager)
        .environmentObject(appDelegate.transcriptionManager)
        .frame(width: 900, height: 600)
}
