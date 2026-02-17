# iOS Agent Instructions

iOS app for Vaultaire — secure photo vault with pattern lock and CloudKit sharing.

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
- **pbxproj ID conventions**: Short hex-style IDs (e.g., `001000000`, `SE0000000`). Use consistent prefixes for new additions (`SE` = Share Extension, `TS` = Tests, `SL` = Share Link, `UX` = UX additions).
- **Existing extensions**: ShareExtension (share services)

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

**MANDATORY**: ALL pixel loaders must use the same `PixelAnimation.loading(size:)` preset. No exceptions.

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
- Layout guard: keep the same scaffold (`header -> Spacer -> 280x280 grid -> Spacer -> bottom placeholder/error area`) so the pattern board stays in the same vertical position across screens.

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
- **Progress timer loop**: for background-critical progress updates, prefer `Task.sleep` loops over RunLoop timers.
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
- **Maestro flow root**: In this monorepo, run Maestro from `apps/ios` and use paths like `maestro/flows/...`; root-level `maestro/flows/...` paths will fail.
- **Maestro launch flakiness from system prompts**: iOS permission alerts (camera/notifications) can block helper waits and cause false negatives. In launch helpers, always include optional dismiss taps for `"Don.*Allow"` and `"OK"` before assertions.
- **Maestro export confirmation variance**: Batch/file export may open share sheet directly without an intermediate `"Export"` confirmation button. Keep that confirmation tap optional in export flows.
- **Maestro + TextEditor**: `TextEditor` accessibility IDs may not be discoverable by Maestro/XCTest in some SwiftUI sheets. Use coordinate taps (`point`) as fallback for input focus.
- **Maestro binary source**: `maestro test` launches the app currently installed on the simulator. After code changes, reinstall the freshly built `.app` with `simctl install` before trusting flow results.
- **Link sharing**: URL fragments (#) never reach server. Base58 (Bitcoin alphabet) excludes ambiguous chars. `fullScreenCover` with computed Binding for deep-link sheets.
- **Sheet keyboard jump on lock screen**: For lock-screen sheets that contain text input, set `.presentationDetents([.large])` at the presentation site (`PatternLockView`) to prevent keyboard-triggered detent changes that make the background appear to jump.
- **Lock-screen modal stability**: If keyboard focus in lock-screen recovery/join flows still causes visual background shifts, present those flows with `.fullScreenCover` from `PatternLockView` and ensure lock-screen surfaces are opaque (`Color.vaultBackground`) to prevent any underlying vault content from showing through transitions.
- **Recovery error readability**: In `RecoveryPhraseInputView`, do not use same-color text and tinted error background (`vaultHighlight` on `vaultHighlight` tint). Use the standard error pattern (title/label in `vaultHighlight`, body in `vaultSecondaryText`, `vaultGlassBackground`) so errors stay readable.
- **Top inset seam in VaultView**: `safeAreaInset(edge: .top)` can inject default platform spacing and create a visible gap between search controls and first section header. Set `spacing: 0` for flush layout.
- **Top controls breathing room**: Keep a small intentional bottom inset under the search/filter row (e.g., `topSafeAreaContent` bottom padding) so pull-down states do not crowd the first section edge.
- **Empty-state width fill**: Root empty-state containers in `VaultView` must explicitly claim full width/height (`.frame(maxWidth: .infinity, maxHeight: .infinity)`) before background styling; otherwise narrow-content states (for example shared-vault import cards) can render with black side gutters.
- **Share-sheet presenter reliability**: `UIApplication.shared.connectedScenes.first` + `scene.keyWindow` is not reliable and can make share/download buttons no-op. Always resolve the foreground-active `UIWindowScene`, then an `isKeyWindow` fallback window, then present from top-most visible view controller.
- **Pattern feedback state precedence**: On create-pattern steps that can emit both `validationResult` and `errorMessage`, always clear the other state when setting one. Otherwise stale `validationResult` can mask newer `errorMessage` (or vice versa).
- **Shared invite vault bootstrap**: In `SharedVaultInviteView`, never seed a vault with legacy `VaultIndex(files:nextOffset:totalSize:)`. Always bootstrap via `VaultStorage.loadIndex(with:)` so the index starts with encrypted master key + v3 blob metadata before background import.
- **Shared import decryption mode**: `SharedVaultData.SharedFile.encryptedContent` may be VCSE streaming ciphertext for large files. In join/import flows, always decrypt with `CryptoEngine.decryptStaged(...)` (or streaming-aware APIs), never `CryptoEngine.decrypt(...)` directly.
- **ChangePattern flow state**: Prefer a dedicated flow state type (`ChangePatternFlowState`) with explicit transitions/helpers over ad-hoc per-branch state mutation; this keeps error/validation exclusivity and processing guards deterministic and unit-testable.
- **ChangePattern completion readability**: On `.complete`, avoid rendering step indicator/title chrome and centered spacers that compress phrase content. Use a scroll-safe completion container and `PhraseDisplayCard` so long generated recovery phrases never truncate.
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
- **Photo viewer presentation identity**: Do not drive full-screen photo presentation with `fullScreenCover(item:)` keyed by the current photo index. Use stable boolean presentation plus a separate initial index; index-keyed presentation can reinstantiate the cover during swipes and cause native-paging glitches.
- **Native-like paging fallback**: If `TabView(.page)` still feels unstable under real gestures/content, use `ScrollView(.horizontal)` + `LazyHStack(spacing: 0)` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` for deterministic per-page anchoring.
- **App-wide appearance mode**: For user-selectable dark/light/system, store mode in `AppState`, persist via UserDefaults (`appAppearanceMode`), and apply exclusively via `UIWindow.overrideUserInterfaceStyle`. **Never use `.preferredColorScheme()`** — it conflicts with UIKit overrides and fails to revert from explicit (light/dark) back to system. Use `UIWindow.didBecomeKeyNotification` to catch new windows from fullScreenCovers/sheets.
- **Appearance transition seam guard**: When applying appearance mode, update `window.overrideUserInterfaceStyle` and both `window.backgroundColor` + `rootViewController.view.backgroundColor` together inside a no-animation transaction. This prevents top/bottom safe-area repaint lag.
- **Dark-mode readability tuning**: Keep light tokens unchanged; adjust only dark appearances in color assets (`VaultBackground`, `VaultSurface`, `VaultSecondaryText`, `AccentColor`) so improvements stay global and consistent without per-view overrides.
- **TestFlight upload auth**: If `xcodebuild -exportArchive` fails with `Failed to Use Accounts`, rerun export/upload with ASC API key flags (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`) to avoid Xcode account-session dependency.
- **ASC CLI builds filter**: In `asc` 0.28+, `asc builds list` no longer supports `--version`; use JSON output + `jq` filtering on `.attributes.version`.
- **ASC CLI output flag**: Use `--output json` (not `--json`) for `asc` commands like `asc builds list`/`asc builds info`.
- **TestFlight group assignment**: Do not assume a group named "Internal Testers" is internal; check `asc testflight beta-groups list` and run `asc builds add-groups` when `Internal = false`.
- **ASC internal-group edge**: `asc builds add-groups` can fail with `Cannot add internal group to a build` for true internal-only groups; distribute via a TestFlight group that accepts build assignment (for this app, `Internal Testers`).
- **ASC build indexing lag**: Right after upload, `asc builds latest --version <N>` can return "no pre-release version found." Poll `asc builds list --sort -uploadedDate --limit 20` until the new version appears, then wait for `processingState = VALID` before `add-groups`.
- **ASC indexing timing**: Newly uploaded builds can stay `not-found` for 1-3 minutes, then appear already `VALID`. Keep polling `asc builds list --sort -uploadedDate --limit 20` instead of failing early.
- **ASC group assignment verification**: After `asc builds add-groups`, verify membership with `asc testflight beta-groups relationships get --type builds`; `asc builds info` may not immediately reflect group linkage.
- **ASC publish shortcut**: `asc publish testflight --app <id> --ipa <path> --group \"Internal Testers\" --wait` can upload, wait for processing, and assign group in one command using keychain auth, returning `buildId`, `buildNumber`, and `processingState`.
- **ASC publish noisy prelude**: ASC may print an update notice before command output. Treat it as non-fatal and rely on final JSON (`uploaded`, `processingState`, `buildId`) for pass/fail.
- **TestFlight preflight gate**: Before every TestFlight upload, run full simulator tests and a targeted Maestro smoke set for touched areas (at minimum settings + core unlock/empty/import flows for settings/theme work).
- **BGProcessing upload continuation**: Register `BGTaskScheduler` identifier `app.vaultaire.ios.share-upload.resume` at launch, include it in `BGTaskSchedulerPermittedIdentifiers`, enable `UIBackgroundModes = processing`, and always call `setTaskCompleted(success:)` on every completion path (success/failure/expiration).
- **iCloud backup settings crash guard**: Backup packaging/encryption must never run on the UI actor. In `iCloudBackupManager.performBackup`, offload payload pack + encrypt/checksum/chunk work to background queues and only marshal UI progress updates on main actor.
- **iCloud backup toggle re-entry**: `iCloudBackupSettingsView` can trigger backup from both toggle-change and on-appear paths; always guard `performBackup()` with `isBackingUp` and cancel/reset cleanly when toggled off.
- **Auto-resume entry points**: Do not rely on a manual "Resume Upload" button only. Trigger `resumePendingUploadsIfNeeded` when vault key becomes available (vault unlock / VaultView open) and when app returns active.
- **Shared-vault claim timing**: Never mark a join phrase as `claimed` during download. Only mark claimed after local import/index setup succeeds; otherwise interruption + retry can fail with `alreadyClaimed` and strand the recipient.
- **Parallel chunk downloads**: `downloadChunksParallel` uses bounded TaskGroup (max 4), order-preserving reassembly via `[Int: Data]` dictionary
- **Structured logging**: Subsystem `"app.vaultaire.ios"`, category = class name. `Self.logger` for actors/classes, file-level `let` for `@MainActor` classes with `nonisolated` methods. Levels: trace (sensitive), debug (routine), info (notable), warning (non-fatal), error (failures)
- **TestFlight CLI upload**: Requires App Store Connect API key (.p8). Without it, export IPA locally + use Xcode Organizer to upload.
- **Embrace init thread affinity**: `Embrace.setup(...).start()` must run on `@MainActor` / main queue. Calling it from `Task.detached` can trigger `dispatch_assert_queue` crashes (`HangCaptureService.init`) when analytics is enabled during onboarding.
- **Embrace startup timing**: Starting Embrace inside an async `Task` from `didFinishLaunching` is too late for startup instrumentation and emits SDK warnings. Start synchronously on main thread in `application(_:willFinishLaunchingWithOptions:)`.
- **Embrace consent gate**: Error/breadcrumb capture flows through `Embrace.client`; if `analyticsEnabled` is false (or startup failed), captures are effectively no-ops. For telemetry triage, verify Settings -> "Help improve Vault" is enabled on the reporting build/device.
- **Embrace visibility limit**: OS terminations (`SIGKILL`/jetsam/OOM/watchdog) usually bypass crash handlers, so Embrace may not record them. Use staged breadcrumbs/progress logs around long crypto/upload phases and infer abnormal exits from missing completion markers on next launch.
- **Embrace handled-error ingestion**: Building a failed span alone is not enough for dashboard "Issues" workflows. For handled app errors, emit `Embrace.client?.log(..., severity: .error, type: .exception, stackTraceBehavior: .main)` with scrubbed attributes in addition to span tagging.
- **Share packaging memory rule**: Never decrypt + re-encrypt full vault files into `Data` during sharing. For large files, always stream decrypt to temp URL and stream-encrypt directly into the SVDF writer (`buildFullStreamingFromPlaintext`) to avoid jetsam at 1-2% "Encrypting files...".
- **Pending upload resume memory rule**: Never read `pending_upload/svdf_data.bin` on the main thread just to check resumability. `hasPendingUpload` must stay metadata-only, and resume chunk uploads must stream from file URL instead of building in-memory chunk arrays.
- **Share extension encryption executor**: In `ShareViewController`, never run per-file crypto/thumbnail work on the main actor. Stage attachments with non-main execution (`Task.detached` for heavy sync sections) and keep UI updates on main actor only; otherwise large batches can be terminated by extension watchdog/jetsam near completion.
- **Share extension batch checkpointing**: Write/update staged `manifest.json` after each successfully encrypted file, not only once at the end. This preserves partial progress if the extension process is terminated mid-batch.
- **Share extension provider retention**: Avoid building a long-lived `[NSItemProvider]` attachment array for big shares. Count first, then process providers in streaming order so references are released sooner and extension memory pressure stays lower.
- **Onboarding unlock transition timing**: Do not set `appState.isUnlocked` during onboarding pattern setup. Keep unlock state change at onboarding completion so `ContentView` can render `LoadingView("Unlocking...")` and then trigger the same vault-door transition used by normal lock-screen unlock.
- **Welcome-screen text truncation**: Long onboarding feature copy can truncate with ellipses on smaller heights when `VStack` layout compresses text. Keep Welcome screen inside a `ScrollView` with `minHeight` matching viewport and set feature title/description to non-compressible wrapping (`lineLimit(nil)` + `fixedSize(vertical: true)`).
- **Onboarding trust copy source of truth**: The trust-message step is `ThankYouView`; whenever copy changes there, update `maestro/flows/onboarding/thankyou_screen.yaml` and `maestro/flows/onboarding/skip_paywall.yaml` assertions in the same PR.
- **Onboarding trust screen structure**: `ThankYouView` should follow: top logo image -> "Protected by Design" title -> feature row list -> CTA. Avoid extra subtitle paragraphs between title and list unless explicitly requested.
- **Auto-lock trigger choice matters**: Locking on `UIApplication.willResignActiveNotification` is too aggressive and can interrupt system pickers/import flows. Use `didEnterBackground` for vault auto-lock and gate with `suppressLockForShareSheet` during transient system UI.
- **Onboarding keyboard-safe recovery step**: In `PatternSetupView` recovery mode, avoid `Spacer`-based centering with text input. Use a scrollable recovery content area plus bottom `safeAreaInset` for the primary CTA so keyboard does not hide actions or push the progress/header off-screen.
- **Welcome copy with explicit line breaks**: If onboarding copy includes manual `\n` line breaks, make Maestro assertions whitespace-tolerant (e.g., `\\s*`) instead of exact single-space matching.
- **Trust screen visual parity**: Keep `ThankYouView` visually aligned with onboarding style by using icon-led `FeatureRow` entries (not standalone hero+card blocks) and a scroll-safe layout with pinned CTA.
- **Settings list theme guard**: `VaultSettingsView` must set `.scrollContentBackground(.hidden)` and an explicit `.background(Color.vaultBackground.ignoresSafeArea())` (plus nav-bar toolbar background) or iOS falls back to default grouped black background.
- **All settings subviews theme guard**: Every settings `List`/`Form` screen (App Settings, Appearance, iCloud Backup, etc.) must apply the same theme modifiers (`.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`, root `vaultBackground`, and explicit navigation `.toolbarBackground`) to prevent default black system surfaces in TestFlight/Release.
- **Unlock transition black-flash guard**: Keep a root `Color.vaultBackground.ignoresSafeArea()` in `ContentView` and set explicit `.toolbarBackground(Color.vaultBackground, for: .navigationBar)` in `VaultView`; otherwise the top safe/nav area can flash system black during unlock transitions.
- **Content-sized background trap**: Applying `.background(Color.vaultBackground...)` to a `Group`/narrow content stack only paints that content bounds. For modal/restore screens, always use a full-screen `ZStack` root color layer plus explicit nav-bar background to prevent black side gutters.
- **Multi-upload sharing architecture**: Use `ShareUploadManager` (separate from `BackgroundShareTransferManager` import flow) for concurrent upload jobs, per-job persistence (`Documents/pending_uploads/<jobId>/`), per-job cancel/resume, and owner-fingerprint filtering for cross-vault isolation.
- **Share UI upload model**: Share screen should represent uploads as share-style rows with status badges/actions (`Resume`, `Terminate`, `Show Phrase`) instead of a single global upload banner/state.
- **Share-screen idle timer rule**: While the Share Vault screen is visible, keep `UIApplication.shared.isIdleTimerDisabled = true` if any upload row is running; release it on stop/disappear.
- **Multi-upload state source**: `ShareUploadManager` is the source of truth for concurrent uploads; keep all upload UI and background-resume behavior keyed from per-job state.
- **Staged-import UX parity**: Reuse `VaultView.importProgress` + `localImportProgressContent` for staged imports too. `ImportIngestor` should emit per-file progress (including total importable count that excludes missing `.enc` files) so staged imports never regress to spinner-only feedback.
- **Share screen mode stability**: Do not auto-force `.manageShares` on every background refresh tick when user manually switched to `.newShare`. Keep manual mode sticky and only auto-transition from `.loading`/`.manageShares` based on data presence.
- **Terminate semantics for upload rows**: User-triggered terminate should hard-remove the job immediately (`terminateUpload`) instead of leaving a `.cancelled` row. Cancel task, clear pending disk payload, remove local share record, and run CloudKit/cache cleanup in background while suppressing post-cancel failure state/notifications.
- **Share-start responsiveness**: In `ShareUploadManager`, never run SVDF packaging, index decryption loops, or cache hash computation on `@MainActor`. Run those in detached/background tasks and only marshal status updates back to main actor.
- **Share completion state UX**: Completed/cancelled upload jobs should not render in the Uploads section. Filter terminal statuses on the share screen and refresh active shares so the view transitions to the final shared-state summary.
- **Manager lifecycle for completed uploads**: On successful upload finalization, remove the job from `ShareUploadManager` state (`removeJob`) instead of retaining `.complete` entries. Share history should live in `activeShares`, not upload queue state.
- **Share screen first-paint performance**: `ShareVaultView.initialize()` must render from local index state first (off-main read), then reconcile CloudKit consumed status asynchronously. Do not block first paint on CloudKit checks, and do not reload the full vault index every 1s upload poll tick.
- **Duress + sharing exclusivity**: Treat active uploads as sharing state (not just persisted `activeShares`). Disable duress whenever a vault is shared, already shared, or currently uploading, and auto-clear duress at share-start to prevent same-session policy bypass.
- **Duress ownership scope**: Keep duress configuration at vault level only; app settings must not expose a separate global "Duress pattern" entry.
- **Share-screen idle timer scope**: Idle timer policy for upload progress must be gated by explicit `ShareVaultView` visibility. Background refresh ticks can race with dismissal; never allow off-screen tasks to re-enable global no-sleep.
- **Pending upload directory race**: `pending_uploads/<jobId>` can be created before `state.json` exists while SVDF is being built. Pending-state scans must ignore no-state directories (in-progress) instead of deleting them, or uploads can fail with missing `svdf_data.bin`.
- **Upload finalization without key**: Persist `uploadFinished` in pending upload state after chunks + manifest are complete. If vault key is unavailable, pause and defer local share-record finalization instead of re-uploading chunks on every resume attempt.
- **Detached-task cleanup rule**: For detached transfer/backup tasks, clear manager state and end background task on main queue via a synchronous helper (`runMainSync`) so completion paths don't leave stale `activeTask`/task IDs.
- **No ActivityKit target**: Dynamic Island/Live Activity support was removed. Do not reintroduce `VaultLiveActivity` target, `TransferActivityAttributes`, or `NSSupportsLiveActivities` without an explicit product decision.
- **Shared-vault join import UX**: `VaultView+Grid.importingProgressContent` should use a full-size `VaultSyncIndicator(style: .loading)` with always-visible progress track/percent and stage text (including 0% starting state) so deep-link join flow never appears as a single tiny stuck pixel.
- **SwiftUI `.task(id:)` contract**: The `id` parameter must be `Equatable`. If a view mode enum has associated values, explicitly conform it to `Equatable` before using it as a task id.
- **Maestro text matching**: `assertVisible.text` behaves as full-regex match in many cases. For substring assertions in long alert messages, use `.*<substring>.*`.
- **Maestro premium-gated flows**: Use launch arg `MAESTRO_PREMIUM_OVERRIDE=true` (wired in `SubscriptionManager` under `#if DEBUG`) so join/share flows can bypass paywall deterministically in automation.
