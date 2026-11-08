import SwiftUI
import SwiftData

/// BoringMeeting app entry point
/// This is the main file - program execution starts here
@main
struct BoringMeetingApp: App {
    
    /// AppDelegate manages the menu bar icon
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Main window - shows meeting list
        WindowGroup {
            ContentView()
                .modelContainer(appDelegate.modelContainer)
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.aiModelManager)
                .environmentObject(appDelegate.transcriptionManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    appDelegate.startRecordingFromUI()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appDelegate.isRecording)
            }
        }
    }
}
