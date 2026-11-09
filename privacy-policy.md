# Privacy Policy

**Effective Date: April 10, 2026**

## Introduction
This Privacy Policy for BoringMeeting describes how we handle user information. We do not collect, store on remote servers, or share any personal data with third parties. All processing happens locally on your device.

## Data Collection
The app operates primarily locally on the user's device.
- No personal data (such as name, email, contacts, photos, or location) is collected or transmitted. The only device-related data sent is the anonymous, truncated hash described in "Analytics & Device Telemetry" below.
- We do not create user accounts, track in-app behavior, or use advertising. Apart from the anonymous daily heartbeat described below, no analytics services are used.
- Screen Recording and System Audio Capture: To enable recording of online meetings (e.g., Microsoft Teams, Zoom, and similar platforms)
  for subsequent transcription, the app requests permission for screen recording and microphone access via macOS privacy prompts.
  ScreenCaptureKit is used exclusively to capture system audio output — no video, screenshots, or visual content are ever captured or
  stored. Captured audio includes: System-wide audio output (meeting audio from any app). These recordings are stored exclusively locally
  on your device. They are never uploaded to our servers, shared with third parties, or used for tracking. Recordings exist only until you
   delete them through the app's UI.

Important: These recordings are stored exclusively locally on your device. They are never uploaded to our servers, shared with third parties, or used for tracking. Recordings exist only until you delete them through the app's UI.

## Internet Connection and Downloads
The app requires an internet connection only for:
- Setup to download open source AI/ML models that are needed for the app to function and for.
  - Downloads come directly from external open-source providers.
  - We do not collect or link any personal data to these downloads.
- Checking updates (via AppStore)
- Sending an anonymous heartbeat (see section Analytics & Device Telemetry below)

## Analytics & Device Telemetry
We use Heartbeat to track basic app usage metrics only.

What we collect:
- Truncated device identifier: SHA256 hash of device UUID, using only first 16 characters (leaving 48 characters unused) - non-reversible
- App version number
- One ping per day, maximum

What we do NOT collect:
- No personal data (name, email, phone)
- We do not store IP addresses or geolocation
- No user behavior tracking
- No app interaction logs
- No recording/audio data

Purpose:
We only want to know: "How many unique devices ran our app today?" This helps us understand if people are actually using BoringMeeting.

Technical Details: [Heartbeat](https://github.com/maierru/heartbeat-tracker) is an open-source project. Data sent via HTTPS. One GET request per day while app is running. No data sent after you close the app.


## Data Usage
All data processed by the app — including meeting recordings and transcription results — is handled locally on your device.
- Screen recordings and captured audio are used solely for local transcription of meeting content you choose to record.
- No recording or transcript data leaves your device. Transcription models process content offline.

## Third Parties
We do not use third-party advertising networks, or SDKs that collect personal data.
Open source model providers may have their own terms and licenses for the models themselves, but they do not receive your personal data from us.

## Data Storage and Deletion
- All recordings and processed data remain on your device.
- Storage duration: Until manually deleted by you via the app interface.
- No remote storage or backups occur.

## Policy Changes
We may update this policy from time to time. Please check this page for the latest version.

## Contact
If you have any questions about this Privacy Policy, contact us at [ninilich@tuta.io].

We respect your privacy.
