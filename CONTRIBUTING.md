# Contributing

Thanks for your interest in BoringMeeting.

## Getting started

1. Fork the repository and create a branch from `main`.
2. Build locally: `xcodebuild -scheme BoringMeeting -destination 'platform=macOS' build` (Debug needs no signing).
3. Make your change, keeping it focused and following the style of the surrounding code.
4. Make sure the build passes without errors, and test recording and transcription manually if you touched them.
5. Bump `MARKETING_VERSION` in `BoringMeeting.xcodeproj/project.pbxproj` and add an entry for it to `BoringMeeting/Resources/WhatsNew.json` (code changes only).
6. Open a pull request describing what changed and why.

## CI/CD

PR checks (`.github/workflows/pr-check.yml`), run on every pull request to `main`:

- Build and unit tests (`BoringMeetingTests`) on `macos-latest`, without code signing. Skipped (the check still passes) when only `docs/`, `*.md`, `LICENSE` or `.gitignore` changed
- `MARKETING_VERSION` must be greater than on `main`, and `BoringMeeting/Resources/WhatsNew.json` must have an entry for the new version. Required only when `BoringMeeting/`, `BMeetingCLI/` or `BoringMeeting.xcodeproj/` changed
- Secret scan with gitleaks

Release (`.github/workflows/release-main-unsigned.yml`), runs on push to `main` that touches `BoringMeeting/`, `BMeetingCLI/` or `BoringMeeting.xcodeproj/` (or manually via workflow_dispatch):

- Reads `MARKETING_VERSION` and publishes a GitHub Release `vX.Y.Z` only if it is higher than the latest `v*` tag
- Builds an unsigned DMG with `scripts/build_local_dmg.sh` and attaches it with a `.sha256` file
- Uses the matching `WhatsNew.json` entry as release notes
- Disabled until the repository variable `RELEASE_ENABLED` is set to `true`

The GitHub build is not signed or notarized. The App Store build is made and uploaded manually from Xcode.

To build a DMG locally: `./scripts/build_local_dmg.sh` (output in `dist/`).

## Guidelines

- Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `refactor:`, `docs:`).
- Keep the app local-first: no network calls that send recordings, transcripts or personal data.
- Do not commit secrets or signing certificates. Keep your own `DEVELOPMENT_TEAM` and bundle identifier changes local; don't include them in pull requests.
- For larger changes, open an issue first to discuss the approach.

By contributing you agree that your contribution is licensed under GPL-3.0, the same as the project.
