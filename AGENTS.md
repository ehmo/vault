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
