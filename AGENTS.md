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

### Learnings

- `critique` CLI needs a current Bun (≥1.3) — older Bun versions throw tree-sitter highlight parse errors against `@opentui/core` assets. Run `bun upgrade` before using the tool.
- `critique` shells out to `git diff`; large binary/untracked assets can blow the default stdout buffer. Filter/ignore big files or limit to specific paths when running it.
- **@MainActor + Task{} = main thread work**: On an `@MainActor` class, `Task { ... }` inherits main actor isolation. ALL synchronous code between suspension points runs on the main thread — including crypto, encoding, and I/O. Use `Task.detached(priority: .userInitiated) { ... }` and explicit `await MainActor.run { ... }` or `await self?.method()` for UI updates.
- **JSONEncoder base64-encodes Data fields**: When serializing structs containing `Data` blobs, `JSONEncoder` converts them to base64 strings (~33% size bloat + significant CPU cost). `PropertyListEncoder(.binary)` stores `Data` as raw bytes with near-zero overhead. For large binary payloads, binary plist is dramatically faster.
- **SharedVaultData format versioning**: CloudKit manifest `version` field: v1 = JSON + outer encryption, v2 = JSON + no outer encryption, v3+ = binary plist + no outer encryption. Decoders must check version or auto-detect via `bplist` magic bytes (`data.prefix(6) == Data("bplist".utf8)`).
- **Live Activity pixel grid needs continuous animationStep**: The Dynamic Island pixel grid animation is driven by `animationStep` in ContentState updates. Never gate Live Activity updates on progress changes alone — `animationStep` must flow every timer tick or the animation freezes.
