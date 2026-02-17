# iOS App Design

## Purpose

This document describes the current design of the Vaultaire iOS application in `apps/ios/`.

It focuses on architecture, key flows, state management, background processing, and design-system guardrails.

## Platform and Targets

1. Main app target: `app.vaultaire.ios`
2. Extension target: `app.vaultaire.ios.ShareExtension`
3. Deployment target: iOS 17+
4. Core cloud container: `iCloud.app.vaultaire.shared`
5. App group: `group.app.vaultaire.ios`

## High-Level Design

The app is local-first and key-driven:

1. Pattern input derives a vault key.
2. Key unlocks encrypted vault index/blob data.
3. Wrong pattern shows an empty vault (plausible deniability behavior).
4. Optional cloud flows support sharing and backup.

## Layered Architecture

### 1) App Layer (`App/`)

1. `VaultApp.swift`
   1. App entrypoint.
   2. Scene lifecycle hooks.
   3. Appearance application across windows.
   4. Background task registration hooks.
2. `ContentView.swift`
   1. Root router for onboarding/locked/loading/unlocked states.
   2. Unlock transition behavior.
   3. Full-screen share invite flow entry.

### 2) Core Layer (`Core/`)

#### Crypto (`Core/Crypto/`)

1. `KeyDerivation.swift` - deterministic key derivation from pattern.
2. `CryptoEngine.swift` - encrypt/decrypt, streaming operations, checksums.
3. `PatternSerializer.swift` - pattern serialization helpers.

#### Storage (`Core/Storage/`)

1. `VaultStorage.swift` - primary encrypted blob/index persistence.
2. `EncryptedBlob.swift` - low-level blob operations.
3. `StagedImportManager.swift` and `ImportIngestor.swift` - app-group staged import pipeline.
4. `iCloudBackupManager.swift` - private CloudKit backup/restore (chunked v2 backup format).
5. `SecureDelete.swift`, `FileUtilities.swift` - deletion and filesystem helpers.

#### Sharing (`Core/Sharing/`)

1. `CloudKitSharingManager.swift`
   1. Shared vault upload/download.
   2. Chunked public CloudKit records.
   3. Manifest/policy management.
2. `ShareUploadManager.swift`
   1. Concurrent upload jobs across vaults.
   2. Per-job persistence and resume.
   3. Background processing scheduling.
3. `BackgroundShareTransferManager.swift`
   1. Legacy/bridging manager for transfer orchestration.
4. `ShareSyncManager.swift` + `ShareSyncCache.swift`
   1. Incremental sync by chunk hash.
5. `SVDFSerializer.swift`
   1. Shared vault data format for efficient sync/import.
6. `DeepLinkHandler.swift`, `ShareLinkEncoder.swift`
   1. Join/share link flow support.

#### Security (`Core/Security/`)

1. `SecureEnclaveManager.swift` - device-bound security primitives.
2. `DuressHandler.swift` - duress vault behavior.
3. `RecoveryPhraseGenerator.swift` + word lists.
4. `GridLetterManager.swift` - vault naming helper from pattern.

#### Billing and Telemetry

1. `SubscriptionManager.swift` - StoreKit 2 entitlements and feature gates.
2. `EmbraceManager.swift`, `AnalyticsManager.swift`, `TelemetryManager.swift` - diagnostics and analytics wrappers.

### 3) Feature Layer (`Features/`)

1. Onboarding
2. Pattern lock
3. Vault viewer and file operations
4. Sharing (owner + invitee screens)
5. Settings (app-level and per-vault)
6. Camera capture flow

### 4) UI Layer (`UI/`)

1. `VaultTheme.swift` - semantic color and style tokens.
2. Shared components:
   1. Pixel loaders (`PixelAnimation`)
   2. Sync indicators
   3. Toasts, banners, phrase actions
   4. Pattern validation feedback

## State and Navigation Design

1. `AppState` is `@Observable` and `@MainActor`.
2. Root state controls:
   1. onboarding visibility
   2. lock/unlock state
   3. loading state
   4. current vault key/pattern
   5. shared-vault mode flags
   6. global appearance mode
3. Feature screens mostly own local view state and call singleton managers for long-running work.

## Data Model Design

1. Vault data is persisted as encrypted index + encrypted blob payloads.
2. File metadata is represented via `VaultFile`/`VaultMetadata` and `VaultFileItem` view models.
3. Sharing records and policies are persisted both locally and in CloudKit.
4. Pending upload states are persisted to documents directories for resume.

## Background Work Design

### Share Uploads

1. Jobs are persisted in `pending_uploads/<jobId>/`.
2. Resume can trigger from:
   1. app lifecycle transitions
   2. vault unlock/key availability
   3. `BGProcessingTask` callbacks
3. Upload state tracks progress, status, and resumability.

### Staged Imports

1. Share extension writes encrypted staged artifacts to app-group storage.
2. Main app ingests staged files after unlock.
3. Progress is displayed with per-file progression (not spinner-only).

### iCloud Backup

1. Backup payload is packed off-main.
2. Encrypt/chunk occurs off-main.
3. Upload uses chunk records in private CloudKit DB.
4. Restore supports existing backup formats with integrity checks.

## Cloud Data Design

### Public DB (Sharing)

1. Manifest type: `SharedVault`
2. Chunk type: `SharedVaultChunk`
3. One-time phrase workflow:
   1. phrase-derived lookup
   2. claim semantics
   3. revocation + policy updates

### Private DB (Backups)

1. Manifest type: `VaultBackup`
2. Chunk type: `VaultBackupChunk`
3. v2 chunked format preferred for larger payloads.

## UX and Design-System Invariants

1. Semantic token colors only for app surfaces.
2. Unified pattern-board placement across lock/create/restore contexts.
3. Unified pixel loader style using `PixelAnimation.loading(size:)`.
4. Settings screens enforce themed list/background/nav surfaces.
5. Appearance mode applied globally via UIKit window style override.

## Security Model (Implementation View)

1. Pattern-derived keys gate vault decryption.
2. Recovery phrase flows exist for account-less recovery.
3. Duress behavior is vault-scoped and sharing-aware.
4. Sensitive operations avoid silent failures where security state may drift.

## Observability and Diagnostics Design

1. `os.Logger` categories per subsystem.
2. Embrace hooks for breadcrumbs, errors, and spans.
3. Release troubleshooting relies on structured logs and deterministic progress markers.

## Testing Design

1. Unit/integration tests via `VaultTests` in simulator.
2. Maestro flows in `apps/ios/maestro/flows` for major user journeys:
   1. onboarding
   2. lock/unlock
   3. import/export
   4. settings/appearance
   5. sharing/join/revoke
3. TestFlight release process requires passing simulator tests and targeted Maestro smoke flows.

## Design Constraints and Non-Goals

1. iOS background execution remains best-effort despite robust resume handling.
2. No ActivityKit / Dynamic Island path in the current architecture.
3. No account-based multi-device identity system.
4. No backend service dependency for core local vault operations.

## Related Documents

1. `docs/security-model.md`
2. `docs/architecture.md` (legacy broad architecture reference)
3. `apps/ios/DESIGN.md`
4. `apps/ios/docs/sharing.md`
5. `apps/ios/docs/storage.md`
