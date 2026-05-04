# SpamShield

iOS Call Directory Extension that blocks numbers you mark as spam, plus a SwiftUI host app for managing the list. Built to develop on Windows: write code locally, push, GitHub Actions builds on a macOS runner and uploads to TestFlight.

## What it does

- Maintains a personal blocklist of phone numbers
- Registers them with iOS via a Call Directory Extension, so calls from those numbers are auto-blocked at the system level (same mechanism Hiya / RoboKiller use)
- Optionally labels numbers (e.g. "Tax Relief Spam") so even calls that aren't blocked get a clear caller-ID label

## What it does NOT do (because iOS doesn't allow it)

- Read or delete voicemails. iOS does not expose voicemail content or storage to third-party apps.
- Delete entries from Call History. Same reason.
- Filter calls by content / transcript. CallKit blocks by phone number only.

A planned follow-up is a separate server piece that ingests carrier voicemail-to-email transcripts, runs keyword detection ("tax relief", "loan", etc.), and pushes the originating number into this app's blocklist over the network so future calls from that number get auto-blocked.

## Architecture

```
App (SwiftUI)         ←  user adds/removes numbers, hits "Reload"
    │
    ├── BlocklistStore (App Group UserDefaults: group.com.thomashart.SpamShield)
    │
CallDirectory Extension  ← reads BlocklistStore on every reload, hands list to iOS
```

Two targets, one shared App Group container, one bundle prefix `com.thomashart.SpamShield`.

## Project layout

```
project.yml                  XcodeGen spec — generates the .xcodeproj on CI
App/
  SpamShieldApp.swift        @main app entry
  ContentView.swift          List UI for managing numbers
  BlocklistStore.swift       Shared storage helper
  Info.plist
  SpamShield.entitlements    App Group
CallDirectory/
  CallDirectoryHandler.swift The CXCallDirectoryProvider subclass
  Info.plist
  CallDirectory.entitlements App Group
fastlane/
  Fastfile                   `beta` lane: sign, build, upload to TestFlight
  Appfile
.github/workflows/build.yml  GHA macOS runner build + TestFlight upload
```

## CI build flow

1. Push to `main`
2. macOS runner installs Xcode + XcodeGen
3. `xcodegen generate` produces `SpamShield.xcodeproj` from `project.yml`
4. fastlane builds with auto-signing (App Store Connect API key) and uploads to TestFlight
5. TestFlight processes the build (~10-15 min)
6. Open TestFlight on iPhone, install, run

End-to-end, push-to-phone is ~25 min the first time. Repeat builds are faster.

## Required GitHub secrets

Set under repo Settings → Secrets and variables → Actions:

| Secret | What it is |
|---|---|
| `APPLE_TEAM_ID` | 10-char team ID from developer.apple.com → Membership |
| `APP_STORE_CONNECT_KEY_ID` | API key ID from App Store Connect → Users and Access → Integrations → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from the same screen |
| `APP_STORE_CONNECT_API_KEY` | The downloaded `.p8` file, base64-encoded (`base64 -w0 AuthKey_XXX.p8`) |

You also need to create the app record in App Store Connect once (My Apps → New → bundle id `com.thomashart.SpamShield`). Do that after enrollment lands.

## Running locally (if you ever borrow a Mac)

```sh
brew install xcodegen
xcodegen generate
open SpamShield.xcodeproj
```

Then use Xcode's automatic signing with your team and run on a connected iPhone.

## Deploying

Commit and push to `main`. Watch the Actions tab. When the build is green, install via TestFlight on the iPhone, then go to **Settings → Phone → Call Blocking & Identification** and toggle SpamShield on.
