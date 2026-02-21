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

**Pairing**: Device is paired. If re-pairing needed:
```bash
xcrun devicectl manage pair --device 00008140-001A00141163001C
# Accept "Trust This Computer?" on phone, re-run once if it fails first time
```

### Build → Install → Launch (device)

```bash
xcodebuild \
  -workspace apps/ios/Vault.xcodeproj/project.xcworkspace \
  -scheme Vault \
  -configuration Debug \
  -destination "id=00008140-001A00141163001C" \
  -derivedDataPath /tmp/VaultDevice \
  build

xcrun devicectl device install app \
  --device 00008140-001A00141163001C \
  /tmp/VaultDevice/Build/Products/Debug-iphoneos/Vault.app

xcrun devicectl device process launch \
  --device 00008140-001A00141163001C \
  app.vaultaire.ios
```

### Build & Test (simulator)

```bash
# Get UUID first
xcrun simctl list devices available

xcodebuild -project Vault.xcodeproj -scheme Vault \
  -destination 'platform=iOS Simulator,id=<UUID>' \
  -configuration Debug build

xcodebuild -project Vault.xcodeproj -scheme Vault \
  -destination 'platform=iOS Simulator,id=<UUID>' \
  -configuration Debug test
```

Always use `-destination 'id=<UUID>'`, never `-destination 'name=...'` (duplicate names cause ambiguity).

## Critical Learnings (Must Read)

### Concurrency
- `Task.detached` ≠ background time. Wrap long work in `beginBackgroundTask`/`endBackgroundTask`
- `@MainActor` singletons need `await` when called from `Task{}`/`Task.detached{}`. Verify ALL call sites after changes — this has regressed repeatedly in `scheduleSync`.
- Never use `Task.detached` inside `@MainActor @Observable` classes — mutating `@Observable` from background causes `swift_retain` crash in SwiftUI body
- Offload crypto/I/O to detached tasks, use `await MainActor.run {}` for UI updates only

### CloudKit
- `CKRecord.save()` = INSERT. To UPDATE: fetch existing record first, modify, then save
- Always wrap in retry (3 retries + exponential backoff). Respect `CKError.retryAfterSeconds`
- `CKError.serverRecordChanged` (code 14) = record already exists. Fetch-or-create is mandatory
- After initial upload, always seed `ShareSyncCache` — incremental sync with empty cache = CKError 14 on all chunks

### Security
- Never `try?` on security paths (duress, file deletion, recovery). Use `do/catch` + Sentry
- `Data(repeating: 0)` ≠ proper key. Use `SymmetricKey(size: .bits256)`
- Never use bare `VaultIndex(files:nextOffset:totalSize:)` for new vault creation — use `VaultStorage.shared.loadIndex(with:)` (handles master key + blob)

### UI Patterns
- `@Observable` (not `ObservableObject`), `@Environment(AppState.self)` for DI
- ALL `List`/`Form` screens: `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`, root `.background(Color.vaultBackground)`
- Sheets with text input: root MUST have `.ignoresSafeArea(.keyboard)` — parent's doesn't propagate into sheets. **Regressed 3+ times.** Affected screens: RecoveryPhraseInputView, JoinVaultView, SharedVaultInviteView, CustomRecoveryPhraseInputView
- Pattern grid position: use fixed heights only — subtitle `44pt`, feedback `80pt`, absent buttons with `.hidden()`
- Onboarding hero images: `Assets.xcassets` with explicit 1x/2x/3x variants

### Sharing & Uploads
- Share extension: run crypto/thumbnails off-main actor; UI updates on main only
- Never load full encrypted files into `Data`. Stream decrypt → temp URL → stream encrypt
- Background uploads: call `setTaskCompleted(success:)` on EVERY path (success/failure/expiration)

### Maestro E2E (Mandatory for UI Changes)
- New screen → new `.yaml` flow; new element → add `accessibilityIdentifier` + assertion
- Run from `apps/ios/`: `maestro test maestro/flows/<path>.yaml`
- No `wait` (use `waitForAnimationToEnd`); no `../` in `addMedia` paths
- Launch arg `-MAESTRO_PREMIUM_OVERRIDE=true` bypasses paywall in DEBUG
- After build, run `simctl install` before Maestro — Maestro tests the installed app, not the build output

### Build & Deploy
- **Physical device**: Use `xcrun devicectl` commands above — no TestFlight needed for dev
- **TestFlight**: Check `asc builds list` BEFORE uploading (avoid "Redundant Binary Upload")
- **Upload limit reached?**: Bump `MARKETING_VERSION` (e.g., 1.0.1 → 1.0.2)
- **ASC API key**: `-authenticationKeyPath ~/.private_keys/AuthKey_GGJ9L8Y97B.p8 -authenticationKeyID GGJ9L8Y97B -authenticationKeyIssuerID 3c53a69e-b7d6-4d46-a26b-2f2d02c69ccb`
- **Signing**: Debug = Automatic (team UFV835UGV6); Release = Manual + "Vault App Store" provisioning profile
- **Sentry dSYM script**: Must be LAST build phase (after Embed Foundation Extensions) to avoid dependency cycle

## Pattern Consistency (MANDATORY)

**Create pattern screens** (PatternSetupView, ChangePatternView create step, etc.):
- Use `PatternValidator.shared.validate()` (min 6 dots + 2 direction changes)
- Show validation feedback in 80pt fixed-height area
- Show strength indicator (shield icon with color)
- On valid: proceed. On invalid: stay, show errors.

**Confirm pattern screens**:
- Show "Patterns don't match" with 2.5s auto-clear
- No validation feedback/strength — match error only

**Unlock/verify screens**:
- 6-dot minimum check only
- No feedback/strength UI

## Learnings Archive

Full session history and grouped pitfalls: `.scratch-pad.md`
