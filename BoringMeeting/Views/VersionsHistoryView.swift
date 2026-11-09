import SwiftUI

struct VersionsHistoryView: View {
    let releases: [WhatsNewService.ReleaseNote]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Versions history")
                    .font(.title2)
                    .fontWeight(.semibold)

                if releases.isEmpty {
                    Text("No release notes available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Version \(release.version)")
                                .font(.headline)

                            Text(release.title)
                                .font(.subheadline)

                            if !release.highlights.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(release.highlights, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                            Text(item)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }

                            if let details = release.details, !details.isEmpty {
                                Text(details)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
