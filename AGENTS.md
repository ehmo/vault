# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
- **COMMIT AND PUSH AFTER EVERY SUCCESSFUL BUILD** — don't accumulate changes. If `xcodebuild` succeeds, immediately `git add`, `git commit`, `git push`. Small, frequent commits are better than one giant commit at the end. This prevents losing work and makes rollbacks easier.

After every task update AGENTS.md with the learnings you just made so you don't repeat the same mistake.

## Scratch Pad (Continual Learning)

A persistent scratch pad at `.scratch-pad.md` tracks errors, corrections, preferences, and learnings across sessions.

**Session Start**: Read `.scratch-pad.md` before doing any work. Apply logged preferences and anticipated improvements.

**Session End**: Update `.scratch-pad.md` with:
1. **Session Log** entry — query summary, approach, errors, corrections, key learnings
2. **Error Tracker** updates — new errors encountered, root causes, preventive measures
3. **Corrections and Preferences** — any user corrections or preference changes
4. **Anticipated Improvements** — proactive fixes for future sessions based on patterns
5. **Cumulative Learnings** — update high-level improvement summary

**Rules**:
- Every session gets a numbered entry in the Session Log
- By session 3+, proactively apply patterns from logged errors/preferences
- Reference specific past sessions when applying learnings (e.g., "From Session 2, user prefers...")
- Keep entries concise — this is a working reference, not a journal
- Commit `.scratch-pad.md` changes alongside code changes

## Project Knowledge

### Xcode Project Structure

- **Bundle ID**: `app.vaultaire.ios`
- **Team**: `UFV835UGV6`
- **Deployment target**: iOS 17.0
- **App group**: `group.app.vaultaire.ios`
- **pbxproj ID conventions**: This project uses short hex-style IDs (e.g., `001000000`, `LA0000000`). Use a consistent prefix for new targets (e.g., `LA` for Live Activity, `SE` for Share Extension).
- **Existing extensions**: ShareExtension (share services), VaultLiveActivityExtension (Live Activity widget)

### Adding a Widget / App Extension Target to pbxproj

When adding a new extension target manually to `project.pbxproj`, you need ALL of these sections — missing any one causes Xcode to fail silently or at build time:

1. **PBXBuildFile** — one entry per source file per target (same file in two targets = two build file entries with different IDs)
2. **PBXFileReference** — one per new file + one for the `.appex` product
3. **PBXContainerItemProxy** — links the main app to the extension target
4. **PBXCopyFilesBuildPhase** — "Embed Foundation Extensions" phase in the main app target, `dstSubfolderSpec = 13`
5. **PBXTargetDependency** — main app depends on extension target
6. **PBXFrameworksBuildPhase** — even if empty, the extension needs one
7. **PBXResourcesBuildPhase** — even if empty
8. **PBXSourcesBuildPhase** — all source files for the extension
9. **PBXGroup** — group for the extension's directory
10. **PBXNativeTarget** — the extension target itself, `productType = "com.apple.product-type.app-extension"`
11. **XCBuildConfiguration** — Debug + Release configs for the extension. Must include `SKIP_INSTALL = YES` and runpath `@executable_path/../../Frameworks`
12. **XCConfigurationList** — references the two configs above
13. **PBXProject updates** — add target to `targets` array and `TargetAttributes`
14. **Products group** — add the `.appex` product reference
15. **Main target updates** — add embed phase to `buildPhases`, add dependency to `dependencies`

**Shared files between targets**: Create separate PBXBuildFile entries with different IDs pointing to the same PBXFileReference. Example: `TransferActivityAttributes.swift` has build file `LA0000001` (main target) and `LA0000003` (widget target), both referencing file ref `LA0000000`.

**Widget extension Info.plist is REQUIRED**: Even with `GENERATE_INFOPLIST_FILE = YES`, WidgetKit extensions MUST have a manual Info.plist containing the `NSExtension` → `NSExtensionPointIdentifier` = `com.apple.widgetkit-extension` entry. Without this, the app builds fine but **fails to install on the simulator** with `IXErrorDomain Code: 2` / "extensionDictionary must be set in placeholder attributes". Set `INFOPLIST_FILE = VaultLiveActivity/Info.plist` in the extension's build settings alongside `GENERATE_INFOPLIST_FILE = YES` — Xcode merges both.

### ActivityKit / Live Activities

- `NSSupportsLiveActivities = YES` must be in the **main app's** Info.plist, not the widget's
- Widget extensions cannot use `Timer.publish()` — use `TimelineView(.animation(minimumInterval:))` for animations
- `Activity.request()` is called from the main app, not the widget
- The widget only provides the UI via `ActivityConfiguration`
- `ActivityAuthorizationInfo().areActivitiesEnabled` guards against devices/settings where Live Activities are disabled
- End activities with `.after(.now + 5)` dismissal policy for auto-dismiss

### Available Simulators

Check available simulators before building. As of this workspace:
- No "iPhone 16" simulator — use `iPhone 17 Pro` or other available devices
- Run `xcodebuild -showdestinations -scheme Vault` to list available destinations

### Build Command

```bash
xcodebuild -project Vault.xcodeproj -scheme Vault \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build 2>&1 | tail -50
```

### SwiftUI Patterns in This Codebase

- Uses `@Observable` (not `ObservableObject`) — iOS 17+ Observation framework
- `@Environment(AppState.self)` pattern for dependency injection
- `BackgroundShareTransferManager.shared` is a singleton accessed directly (not via environment)
- Transfer status uses enum with associated values: `.uploading(progress:total:)`, `.importComplete`, etc.
- **PixelAnimation trail effect requires Timer.publish, NOT TimelineView**: The in-app pixel grid creates its trail by overlapping `withAnimation` transitions (`animationDuration > timerInterval`). `TimelineView` re-evaluates its body closure on each tick, resetting the view tree and disrupting in-flight implicit animations. `Timer.publish` + `.onReceive` only mutates `@State` without re-evaluating the body, preserving the overlap. This matches the Dynamic Island's `LivePixelGrid` which computes the trail explicitly.

### Learnings

- `critique` CLI needs a current Bun (≥1.3) — older Bun versions throw tree-sitter highlight parse errors against `@opentui/core` assets. Run `bun upgrade` before using the tool.
- `critique` shells out to `git diff`; large binary/untracked assets can blow the default stdout buffer. Filter/ignore big files or limit to specific paths when running it.
- **@MainActor + Task{} = main thread work**: On an `@MainActor` class, `Task { ... }` inherits main actor isolation. ALL synchronous code between suspension points runs on the main thread — including crypto, encoding, and I/O. Use `Task.detached(priority: .userInitiated) { ... }` and explicit `await MainActor.run { ... }` or `await self?.method()` for UI updates.
- **JSONEncoder base64-encodes Data fields**: When serializing structs containing `Data` blobs, `JSONEncoder` converts them to base64 strings (~33% size bloat + significant CPU cost). `PropertyListEncoder(.binary)` stores `Data` as raw bytes with near-zero overhead. For large binary payloads, binary plist is dramatically faster.
- **SharedVaultData format versioning**: CloudKit manifest `version` field: v1 = JSON + outer encryption, v2 = JSON + no outer encryption, v3+ = binary plist + no outer encryption. Decoders must check version or auto-detect via `bplist` magic bytes (`data.prefix(6) == Data("bplist".utf8)`).
- **Live Activity pixel grid needs continuous animationStep**: The Dynamic Island pixel grid animation is driven by `animationStep` in ContentState updates. Never gate Live Activity updates on progress changes alone — `animationStep` must flow every timer tick or the animation freezes.
- **Sharing source files between main app and extensions**: Instead of creating a framework, add separate PBXBuildFile entries for each target pointing to the same PBXFileReference (same pattern as `TransferActivityAttributes.swift` with `LA` prefix IDs). Use `SWIFT_ACTIVE_COMPILATION_CONDITIONS = EXTENSION` in extension build settings, then `#if !EXTENSION` to strip SentryManager/GridLetterManager/main-app-only code from shared files.
- **Keychain sharing between app and extension**: Use `kSecAttrAccessGroup: "group.app.vaultaire.ios"` (the app group ID) in keychain queries for items that need extension access. The extension also needs the app group in its entitlements. Without this, the extension gets a dummy salt → wrong key derivation.
- **Share extension Info.plist**: Use `NSExtensionPrincipalClass` (not `NSExtensionMainStoryboard`) for programmatic UI. Value MUST be module-qualified for Swift classes: `ShareExtension.ShareViewController` (not just `ShareViewController`). Without the module prefix, the system can't find the class and shows a blank white sheet with no error logged.
- **ShareExtension pbxproj IDs use `SE` prefix** (consistent with `LA` for Live Activity).
- **Opening iOS Settings deep links**: Private `App-Prefs:` URL schemes change between iOS versions and are unreliable. `App-Prefs:root=CASTLE` (old iCloud) opens Apps on iOS 17+. Use `SettingsURLHelper.openICloudSettings()` (in `iCloudBackupManager.swift`) as the single source of truth for opening iCloud settings. Currently uses `App-Prefs:root=APPLE_ACCOUNT` with `canOpenURL` check + fallback. **Always use this helper** — never inline `App-Prefs:` URLs directly.
- **iCloud availability checks**: `FileManager.ubiquityIdentityToken` can be non-nil when iCloud isn't actually usable (token exists but container URL is nil). Always use `CloudKitSharingManager.checkiCloudStatus()` (CKAccountStatus) for reliable iCloud availability checks. Catch both `iCloudError.notAvailable` AND `.containerNotFound` when handling backup failures.
- **Keep iCloud unavailable screens in sync**: ShareVaultView and iCloudBackupSettingsView both have iCloud unavailable states. They must show the same UI pattern (full-screen centered VStack, icloud.slash icon, "iCloud Required" title, SettingsURLHelper button, Retry). When changing one, always update the other.
- **CloudKit CKRecord.save() is INSERT for new objects**: `CKRecord(recordType:, recordID:)` creates a NEW record object. When `CKDatabase.save()` is called on it, CloudKit treats it as an INSERT. If a record with that ID already exists, you get `CKError.serverRecordChanged` (code 14, "record to insert already exists"). To UPDATE an existing record, you MUST first fetch it with `CKDatabase.record(for:)`, modify the fetched object, then save it. **Always use a fetch-or-create pattern** (`fetchOrCreateRecord()`) before saving chunk records — never assume a record doesn't exist based on local state alone.
- **CloudKit share sync: initial upload vs incremental sync cache gap**: `BackgroundShareTransferManager.uploadSharedVault()` creates chunk records in CloudKit but does NOT populate the `ShareSyncCache`. When `ShareSyncManager.performSync()` runs later, it reads `previousChunkHashes` from the cache (empty/nil), treats ALL chunks as "new", and tries INSERT → fails with CKError 14. The fix: always fetch existing records before saving, regardless of what the local cache says about chunk history.
- **CameraManager deinit + weak self = crash**: Calling `[weak self]` closures from `deinit` is undefined behavior because Swift can't form a weak reference to an object mid-deallocation. Instead, capture the specific properties you need (e.g., `let session = self.session`) and dispatch without referencing `self`.
- **SwiftUI button press dimming + animation leak**: The default `ButtonStyle` dims buttons on press (~0.2 opacity). Inside a `ZStack`, `.animation(_:value:)` modifiers on sibling views can leak to other views in the same container. Fix: use `.buttonStyle(.plain)` and/or separate animated siblings into distinct overlays to isolate animation contexts.
- **iOS background task expiration handler must end synchronously**: The `beginBackgroundTask` expiration handler runs on the main queue. Must call `endBackgroundTask` before the handler returns — dispatching via `Task { @MainActor in }` creates an async hop that may not execute before iOS suspends the app. Use `MainActor.assumeIsolated` for synchronous access to `@MainActor`-isolated state in the handler. Store `bgTaskId` as a property with an idempotent `endBackgroundExecution()` helper. Always end the previous background task before starting a new one.
- **Transfer status UI must handle all enum cases**: When displaying upload/sync/import status, handle ALL non-idle cases (uploading, failed, complete), not just the happy-path `.uploading`. Users see nothing if only the active state has UI treatment.
