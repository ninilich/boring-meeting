import SwiftUI
import SwiftData

/// Main application window showing meeting history
struct ContentView: View {
    var body: some View {
        MeetingListView()
            .frame(minWidth: 920, minHeight: 500)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Meeting.self, inMemory: true)
}
