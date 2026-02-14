# iOS Agent Instructions

iOS app for Vaultaire — secure photo vault with pattern lock, CloudKit sharing, Live Activities.

## Build

```bash
xcodebuild -project Vault.xcodeproj -scheme Vault \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build 2>&1 | tail -50
```

Check available simulators: `xcodebuild -showdestinations -scheme Vault`

## Xcode Project Structure

- **Bundle ID**: `app.vaultaire.ios`
- **Team**: `UFV835UGV6`
- **Deployment target**: iOS 17.0
- **App group**: `group.app.vaultaire.ios`
- **pbxproj ID conventions**: Short hex-style IDs (e.g., `001000000`, `LA0000000`). Use consistent prefix for new targets (`LA` = Live Activity, `SE` = Share Extension, `TS` = Tests, `SL` = Share Link, `UX` = UX additions).
- **Existing extensions**: ShareExtension (share services), VaultLiveActivityExtension (Live Activity widget)

## Adding a Widget / App Extension Target to pbxproj

Required sections — missing any one causes Xcode to fail silently or at build time:

1. **PBXBuildFile** — one entry per source file per target
2. **PBXFileReference** — one per new file + one for the `.appex` product
3. **PBXContainerItemProxy** — links main app to extension target
4. **PBXCopyFilesBuildPhase** — "Embed Foundation Extensions" in main app, `dstSubfolderSpec = 13`
5. **PBXTargetDependency** — main app depends on extension target
6. **PBXFrameworksBuildPhase** — even if empty
7. **PBXResourcesBuildPhase** — even if empty
8. **PBXSourcesBuildPhase** — all source files for extension
9. **PBXGroup** — group for extension directory
10. **PBXNativeTarget** — `productType = "com.apple.product-type.app-extension"`
11. **XCBuildConfiguration** — Debug + Release, `SKIP_INSTALL = YES`, runpath `@executable_path/../../Frameworks`
12. **XCConfigurationList** — references the two configs
13. **PBXProject updates** — add target to `targets` array and `TargetAttributes`
14. **Products group** — add `.appex` product reference
15. **Main target updates** — embed phase + dependency

**Shared files between targets**: Separate PBXBuildFile entries with different IDs pointing to same PBXFileReference.

**Widget Info.plist**: Even with `GENERATE_INFOPLIST_FILE = YES`, WidgetKit extensions MUST have manual Info.plist with `NSExtension` → `NSExtensionPointIdentifier` = `com.apple.widgetkit-extension`. Without it, builds fine but fails to install (`IXErrorDomain Code: 2`).

## ActivityKit / Live Activities

- `NSSupportsLiveActivities = YES` in **main app's** Info.plist
- Widget extensions: use `TimelineView(.animation(minimumInterval:))` not `Timer.publish()`
- `Activity.request()` from main app, widget only provides UI via `ActivityConfiguration`
- End activities with `.after(.now + 5)` dismissal policy

## Maestro E2E Tests

**MANDATORY**: Every visual or UI change MUST include corresponding Maestro test updates. This is non-negotiable.

- Tests live in `maestro/flows/` organized by feature area
- Every new accessibility identifier must be tested
- Every new screen, button, or user-facing text must have assertions
- Pattern: mirror onboarding tests when adding similar flows elsewhere (e.g., `pattern_confirm_error.yaml` → `join_vault_pattern_validation.yaml`)
- Use `optional: true` for assertions after synthetic swipes (PatternGridView may not register them)
- Use `waitForAnimationToEnd` instead of `wait`
- Run with: `maestro test maestro/flows/<path>.yaml`

**Checklist before committing UI changes:**
1. New screen? → New `.yaml` test flow
2. New button/input? → Add `accessibilityIdentifier`, assert in test
3. Changed text/labels? → Update `assertVisible` text in existing tests
4. Changed flow/navigation? → Update test flow sequence

## PixelAnimation (Loaders)

**MANDATORY**: ALL pixel loaders MUST match the Dynamic Island's `LivePixelGrid` appearance. No exceptions.

- **Canonical preset**: `PixelAnimation.loading(size:)` — perimeter walk `[1,2,3,6,9,8,7,4]`, brightness 3, shadowBrightness 2, timerInterval 0.1, animationDuration 0.3
- **Only vary size** — never create alternate patterns, brightness, or timing
- `syncing(size:)` delegates to `loading(size:)` — it's just a size alias
- `uploading()` and `downloading()` factory methods were removed — they had inconsistent patterns/brightness
- Trail effect requires `Timer.publish` + `.onReceive`, NOT `TimelineView` (which resets view tree and kills in-flight animations)
- When adding a new loader anywhere, use `PixelAnimation.loading(size: N)` — nothing else

## Pattern Board Consistency (MANDATORY)

All pattern grid screens MUST behave identically. There are two categories:

**"Create new pattern" screens** (user draws a new pattern):
- PatternSetupView (onboarding), ChangePatternView (createNew step), JoinVaultView (create step), SharedVaultInviteView (create step)
- MUST use `PatternValidator.shared.validate()` for full validation (min 6 dots + 2 direction changes)
- MUST show validation feedback below grid: errors (red X icon), warnings (yellow triangle, max 2), strength indicator (shield icon with color)
- MUST use fixed 80pt height `Group` for feedback area (prevents grid from jumping)
- MUST use fixed subtitle height `.frame(height: 44, alignment: .top)` (prevents grid shift from different text lengths)
- MUST use `.hidden()` placeholder buttons to keep bottom area consistent across steps
- When pattern is valid: proceed to confirm step. When invalid: stay on create step, show errors in feedback area.

**"Confirm pattern" screens** (user re-draws to confirm):
- PatternSetupView (confirm), ChangePatternView (confirmNew), JoinVaultView (confirm), SharedVaultInviteView (confirm)
- Show "Patterns don't match. Try again." error with 2.5s auto-clear on mismatch
- No validation feedback/strength — only match error

**"Enter existing pattern" screens** (unlock, verify):
- PatternLockView, ChangePatternView (verifyCurrent), RestoreFromBackupView
- Minimal validation only (6-dot minimum)
- No validation feedback/strength

**When adding/modifying ANY pattern screen**: verify it matches the correct category above. Copy the FULL behavior — validation, feedback, errors, haptics, layout constraints — not just the data flow.

## SwiftUI Patterns

- `@Observable` (iOS 17+ Observation framework), not `ObservableObject`
- `@Environment(AppState.self)` for dependency injection
- `BackgroundShareTransferManager.shared` singleton (not via environment)
- Transfer status: enum with associated values (`.uploading(progress:total:)`, `.importComplete`, etc.)

## Learnings

- **@MainActor + Task{} = main thread work**: Use `Task.detached(priority: .userInitiated)` for crypto/I/O, explicit `await MainActor.run { }` for UI updates
- **JSONEncoder base64-encodes Data**: Use `PropertyListEncoder(.binary)` for large binary payloads
- **SharedVaultData versioning**: v1 = JSON + outer encryption, v2 = JSON no encryption, v3+ = binary plist. Auto-detect via `bplist` magic bytes
- **Live Activity pixel grid**: `animationStep` must flow every timer tick — never gate on progress alone
- **Sharing source files**: Separate PBXBuildFile entries per target, `SWIFT_ACTIVE_COMPILATION_CONDITIONS = EXTENSION`, `#if !EXTENSION` guards
- **Keychain sharing**: `kSecAttrAccessGroup: "group.app.vaultaire.ios"` + app group in extension entitlements
- **Share extension Info.plist**: `NSExtensionPrincipalClass` must be module-qualified: `ShareExtension.ShareViewController`
- **iCloud settings deep links**: Use `SettingsURLHelper.openICloudSettings()` — never inline `App-Prefs:` URLs
- **iCloud availability**: Use `CloudKitSharingManager.checkiCloudStatus()` (CKAccountStatus), not `ubiquityIdentityToken`
- **CloudKit CKRecord.save() = INSERT for new objects**: Always fetch-or-create before saving chunk records
- **CloudKit cache gap**: Initial upload doesn't populate ShareSyncCache → first sync tries INSERT on existing records. Always fetch existing records before save.
- **CameraManager deinit**: Never `[weak self]` in deinit closures — capture properties by value
- **SwiftUI animation leak**: `.animation(_:value:)` leaks across ZStack siblings. Use `.buttonStyle(.plain)` and separate overlays
- **Background task expiration**: Use `MainActor.assumeIsolated` in handler, call `endBackgroundTask` synchronously. Store `bgTaskId` as property with idempotent helper.
- **Transfer status UI**: Handle ALL non-idle enum cases, not just `.uploading`
- **Maestro**: No `wait` (use `waitForAnimationToEnd`), no `clearInput` (use `eraseText`), no `../` in `addMedia` paths, `clearKeychain` triggers system dialog, `clearState` resets UserDefaults
- **Maestro + TextEditor**: `TextEditor` accessibility IDs may not be discoverable by Maestro/XCTest in some SwiftUI sheets. Use coordinate taps (`point`) as fallback for input focus.
- **Maestro binary source**: `maestro test` launches the app currently installed on the simulator. After code changes, reinstall the freshly built `.app` with `simctl install` before trusting flow results.
- **Link sharing**: URL fragments (#) never reach server. Base58 (Bitcoin alphabet) excludes ambiguous chars. `fullScreenCover` with computed Binding for deep-link sheets.
- **Sheet keyboard jump on lock screen**: For lock-screen sheets that contain text input, set `.presentationDetents([.large])` at the presentation site (`PatternLockView`) to prevent keyboard-triggered detent changes that make the background appear to jump.
- **Lock-screen modal stability**: If keyboard focus in lock-screen recovery/join flows still causes visual background shifts, present those flows with `.fullScreenCover` from `PatternLockView` and ensure lock-screen surfaces are opaque (`Color.vaultBackground`) to prevent any underlying vault content from showing through transitions.
- **Top inset seam in VaultView**: `safeAreaInset(edge: .top)` can inject default platform spacing and create a visible gap between search controls and first section header. Set `spacing: 0` for flush layout.
- **Top controls breathing room**: Keep a small intentional bottom inset under the search/filter row (e.g., `topSafeAreaContent` bottom padding) so pull-down states do not crowd the first section edge.
- **Pattern feedback state precedence**: On create-pattern steps that can emit both `validationResult` and `errorMessage`, always clear the other state when setting one. Otherwise stale `validationResult` can mask newer `errorMessage` (or vice versa).
- **ChangePattern flow state**: Prefer a dedicated flow state type (`ChangePatternFlowState`) with explicit transitions/helpers over ad-hoc per-branch state mutation; this keeps error/validation exclusivity and processing guards deterministic and unit-testable.
- **Deterministic Change Pattern tests**: Simulator-only test hooks (`change_pattern_test_*`) are available in `ChangePatternView` for Maestro regression flows; they should never gate production behavior.
- **Test target**: `@testable import Vault` with `TEST_HOST` pattern, TS prefix IDs. `xcrun simctl list devices available` before test runs.
- **Streaming encryption**: `CryptoEngine.encryptStreaming(fileURL:originalSize:with:)` reads via FileHandle in 256KB chunks — use for any file >10MB to avoid peak memory spikes
- **Streaming decrypt path**: For temp-file retrieval of VCSE content, parse header from `FileHandle` and stream-decrypt directly to output URL. Avoid loading whole encrypted entries into `Data` first.
- **Share consumed-state lookups**: Fetch consumed states in batch (`consumedStatusByShareVaultIds`) for list/sync paths to avoid N+1 CloudKit/DB reads.
- **VaultView derived data**: Compute filtered/sorted visible files once per render pass and pass that derived data into grid/viewer helpers instead of recomputing in each subview.
- **Crypto fallback safety**: Never use `Data(repeating: 0, count: N)` as crypto key fallback — use `SymmetricKey(size:)` for proper entropy
- **try? on security paths**: `try?` on duress vault setup, file deletion, or recovery data operations hides critical failures. Use `do/catch` + Sentry for anything where silent failure = false sense of security
- **VaultView extensions**: Decomposed into +Grid, +Toolbar, +FanMenu, +SharedVault, +Actions. Keep body in main file, extracted views/methods in extensions.
- **Full-screen photo paging**: Keep `TabView(.page)` pages strictly full-frame/clipped and avoid competing drag gestures on the `TabView` itself; gesture conflicts can leave pages visually between anchors.
- **Parallel chunk downloads**: `downloadChunksParallel` uses bounded TaskGroup (max 4), order-preserving reassembly via `[Int: Data]` dictionary
- **Structured logging**: Subsystem `"app.vaultaire.ios"`, category = class name. `Self.logger` for actors/classes, file-level `let` for `@MainActor` classes with `nonisolated` methods. Levels: trace (sensitive), debug (routine), info (notable), warning (non-fatal), error (failures)
- **TestFlight CLI upload**: Requires App Store Connect API key (.p8). Without it, export IPA locally + use Xcode Organizer to upload.
