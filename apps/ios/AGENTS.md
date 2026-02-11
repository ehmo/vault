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

## SwiftUI Patterns

- `@Observable` (iOS 17+ Observation framework), not `ObservableObject`
- `@Environment(AppState.self)` for dependency injection
- `BackgroundShareTransferManager.shared` singleton (not via environment)
- Transfer status: enum with associated values (`.uploading(progress:total:)`, `.importComplete`, etc.)
- **PixelAnimation trail**: requires `Timer.publish` + `.onReceive`, NOT `TimelineView` (which resets view tree and kills in-flight animations)

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
- **Link sharing**: URL fragments (#) never reach server. Base58 (Bitcoin alphabet) excludes ambiguous chars. `fullScreenCover` with computed Binding for deep-link sheets.
- **Test target**: `@testable import Vault` with `TEST_HOST` pattern, TS prefix IDs. `xcrun simctl list devices available` before test runs.
