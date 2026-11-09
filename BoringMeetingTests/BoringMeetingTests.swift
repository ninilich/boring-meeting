//
//  BoringMeetingTests.swift
//  BoringMeetingTests
//
//  Created by ninilich on 09.02.26.
//

import XCTest
@testable import BoringMeeting

final class BoringMeetingTests: XCTestCase {
    private var originalSuppressedVersion = ""
    private var originalLastSeenVersion = ""

    override func setUpWithError() throws {
        let settings = AppSettings.shared
        originalSuppressedVersion = settings.suppressedWhatsNewVersion
        originalLastSeenVersion = settings.lastSeenWhatsNewVersion
        settings.suppressedWhatsNewVersion = ""
        settings.lastSeenWhatsNewVersion = ""
    }

    override func tearDownWithError() throws {
        let settings = AppSettings.shared
        settings.suppressedWhatsNewVersion = originalSuppressedVersion
        settings.lastSeenWhatsNewVersion = originalLastSeenVersion
    }

    @MainActor
    func testReleaseNoteLookupByVersion() throws {
        let service = makeService(version: "1.0", json: sampleManifest)

        let release = service.releaseNote(for: "1.0")

        XCTAssertEqual(release?.title, "Stability and UX improvements")
        XCTAssertEqual(release?.highlights.count, 2)
    }

    @MainActor
    func testShouldShowOnLaunchWhenNotSuppressed() throws {
        let settings = AppSettings.shared
        settings.suppressedWhatsNewVersion = ""
        let service = makeService(version: "1.0", json: sampleManifest)

        XCTAssertTrue(service.shouldShowOnLaunch(settings: settings))
    }

    @MainActor
    func testShouldNotShowWhenSuppressedForCurrentVersion() throws {
        let settings = AppSettings.shared
        settings.suppressedWhatsNewVersion = "1.0"
        let service = makeService(version: "1.0", json: sampleManifest)

        XCTAssertFalse(service.shouldShowOnLaunch(settings: settings))
    }

    @MainActor
    func testSuppressionAffectsOnlyCurrentVersion() throws {
        let settings = AppSettings.shared
        settings.suppressedWhatsNewVersion = ""

        let firstVersionService = makeService(version: "1.0", json: sampleManifest)
        firstVersionService.setSuppressedForCurrentVersion(true, settings: settings)

        XCTAssertEqual(settings.suppressedWhatsNewVersion, "1.0")

        let nextVersionService = makeService(version: "1.1", json: sampleManifest)
        XCTAssertTrue(nextVersionService.shouldShowOnLaunch(settings: settings))
    }

    @MainActor
    func testInvalidManifestFailsClosed() throws {
        let settings = AppSettings.shared
        settings.suppressedWhatsNewVersion = ""

        let invalidData = "{not-json".data(using: .utf8)
        let service = WhatsNewService(
            manifestLoader: { invalidData },
            appVersionProvider: { "1.0" }
        )

        XCTAssertNil(service.currentReleaseNote())
        XCTAssertFalse(service.shouldShowOnLaunch(settings: settings))
    }

    @MainActor
    private func makeService(version: String, json: String) -> WhatsNewService {
        let data = json.data(using: .utf8)
        return WhatsNewService(
            manifestLoader: { data },
            appVersionProvider: { version }
        )
    }

    private let sampleManifest = """
    {
      \"schemaVersion\": 1,
      \"versions\": [
        {
          \"version\": \"1.0\",
          \"title\": \"Stability and UX improvements\",
          \"highlights\": [
            \"Improved startup reliability\",
            \"New About shortcuts\"
          ],
          \"details\": \"Small quality-of-life improvements across the app.\"
        },
        {
          \"version\": \"1.1\",
          \"title\": \"More audio resilience\",
          \"highlights\": [
            \"More robust capture pipeline\"
          ],
          \"details\": null
        }
      ]
    }
    """
}
