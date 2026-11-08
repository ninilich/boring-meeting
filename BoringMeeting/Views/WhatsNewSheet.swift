import SwiftUI

struct WhatsNewSheet: View {
    let release: WhatsNewService.ReleaseNote
    @Binding var dontShowAgain: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new in version \(release.version)?")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()
            }

            Text(release.title)
                .font(.headline)

            if !release.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(release.highlights, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16)
                            Text(item)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let details = release.details, !details.isEmpty {
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Do not show again for this version", isOn: $dontShowAgain)

            HStack {
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 620)
    }
}
