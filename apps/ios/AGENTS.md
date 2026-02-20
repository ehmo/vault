# iOS Agent Instructions

SwiftUI app with CloudKit sharing. Stack: iOS 17+, `@Observable`, CloudKit, CryptoKit.

## Physical Device — iPhone 16 (primary test device)

| Field | Value |
|-------|-------|
| Name | iPhone |
| Model | iPhone 16 (iPhone17,3) |
| Serial | GGp2CWCRF4 |
| UDID | `00008140-001A00141163001C` |
| OS | iOS 26.1 |
| Connection | USB |

**Pairing**: Device is paired. If re-pairing needed (e.g. after cable swap or Xcode reset):
```bash
xcrun devicectl manage pair --device 00008140-001A00141163001C
# Accept "Trust This Computer?" on the phone, then re-run if it fails first time
```

### Build → Install → Launch (device)

```bash
# Build for device (Automatic signing — auto-registers device with team UFV835UGV6)
xcodebuild \
  -workspace apps/ios/Vault.xcodeproj/project.xcworkspace \
  -scheme Vault \
  -configuration Debug \
  -destination "id=00008140-001A00141163001C" \
  -derivedDataPath /tmp/VaultDevice \
  build

# Install
xcrun devicectl device install app \
  --device 00008140-001A00141163001C \
  /tmp/VaultDevice/Build/Products/Debug-iphoneos/Vault.app

# Launch
xcrun devicectl device process launch \
  --device 00008140-001A00141163001C \
  app.vaultaire.ios
```

### Build & Test (simulator fallback)

```bash
# Build
xcodebuild -project Vault.xcodeproj -scheme Vault \
  -destination 'platform=iOS Simulator,id=<UUID>' \
  -configuration Debug build

# Test
xcodebuild -project Vault.xcodeproj -scheme Vault \
  -destination 'platform=iOS Simulator,id=<UUID>' \
  -configuration Debug test
```

Get simulator UUID: `xcrun simctl list devices available`

## Critical Learnings (Must Read)

### Concurrency
- `Task.detached` ≠ background execution time. Wrap long work in `beginBackgroundTask`/`endBackgroundTask`
- `@MainActor` singletons need `await` when called from `Task{}`. Always verify call sites after changes
- Offload crypto/I/O to detached tasks, use `await MainActor.run {}` for UI updates only

### CloudKit
- `CKRecord.save()` = INSERT. To UPDATE: fetch existing record first, modify, then save
- Always wrap in retry logic (3 retries + exponential backoff). Respect `CKError.retryAfterSeconds`
- `CKError.serverRecordChanged` (code 14) = record already exists. Fetch-or-create pattern required

### Security
- Never `try?` on security paths (duress, file deletion, recovery). Use `do/catch` + Sentry
- `Data(repeating: 0)` ≠ proper key. Use `SymmetricKey(size: .bits256)` for entropy

### UI Patterns
- `@Observable` (not `ObservableObject`), `@Environment(AppState.self)` for DI
- ALL `List`/`Form` screens need: `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`, root `.background(Color.vaultBackground)`
- Lock-screen sheets with text input: MUST use `.ignoresSafeArea(.keyboard)` on root
- Pattern grid position: fixed heights only — subtitle `44pt`, feedback `80pt`, placeholder buttons with `.hidden()`
- Onboarding hero/art images should live in `Assets.xcassets` with explicit 1x/2x/3x variants; avoid ad-hoc runtime scaling of source files

### Sharing & Uploads
- Share extension: Run crypto/thumbnails off-main actor. Keep UI updates on main only
- Never load full encrypted files into `Data` for sharing. Stream decrypt → temp URL → stream encrypt
- Background uploads: Call `setTaskCompleted(success:)` on EVERY path (success/failure/expiration)

### Maestro E2E (Mandatory for UI Changes)
- New screen → New `.yaml` flow
- New element → Add `accessibilityIdentifier` + assertion
- Run from `apps/ios/`: `maestro test maestro/flows/<path>.yaml`
- No `wait` (use `waitForAnimationToEnd`), no `../` in `addMedia` paths
- Launch arg `MAESTRO_PREMIUM_OVERRIDE=true` for paywall bypass in DEBUG

### Build & Deploy
- **Physical device**: Use `xcrun devicectl` commands above — no TestFlight needed for dev testing
- TestFlight: Check `asc builds list` BEFORE uploading (avoid "Redundant Binary Upload")
- Upload limit reached? Bump `MARKETING_VERSION` (e.g., 1.0.1 → 1.0.2)
- ASC API key: `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` flags
- Signing: Debug uses Automatic (team UFV835UGV6); Release uses Manual + "Vault App Store" provisioning profile

## Pattern Consistency (MANDATORY)

**Create pattern screens** (PatternSetupView, ChangePatternView create step, etc.):
- Use `PatternValidator.shared.validate()` (min 6 dots + 2 direction changes)
- Show validation feedback in 80pt fixed-height area
- Show strength indicator (shield icon with color)
- On valid: proceed. On invalid: stay, show errors.

**Confirm pattern screens**:
- Show "Patterns don't match" error with 2.5s auto-clear
- No validation feedback/strength — only match error

**Unlock/verify screens**:
- Minimal validation only (6-dot minimum)
- No feedback/strength UI

## Learnings Archive

Full detailed history: `.scratch-pad.md` (2,800+ lines)
Session errors and corrections: See scratch-pad Error Tracker section
