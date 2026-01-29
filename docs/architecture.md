# Architecture

## Project Structure

```
Vault/
├── App/                          # Application entry point
│   ├── VaultApp.swift           # @main, AppState, security setup
│   └── ContentView.swift        # Root view router
│
├── Core/                         # Core functionality
│   ├── Crypto/                  # Encryption and key management
│   │   ├── CryptoEngine.swift   # AES-256-GCM encryption
│   │   ├── KeyDerivation.swift  # PBKDF2 key derivation
│   │   └── PatternSerializer.swift
│   │
│   ├── Storage/                 # Persistent storage
│   │   ├── VaultStorage.swift   # Blob-based file storage
│   │   ├── EncryptedBlob.swift  # Low-level blob operations
│   │   ├── SecureDelete.swift   # Secure file wiping
│   │   └── iCloudBackupManager.swift
│   │
│   ├── Security/                # Security features
│   │   ├── SecureEnclaveManager.swift  # Device-bound keys
│   │   ├── DuressHandler.swift  # Duress vault logic
│   │   ├── WipePolicy.swift     # Auto-wipe configuration
│   │   ├── RecoveryPhraseGenerator.swift
│   │   └── WordLists.swift
│   │
│   └── Sharing/                 # Vault sharing
│       ├── CloudKitSharingManager.swift  # Chunked upload/download, claim, revoke
│       └── ShareSyncManager.swift        # Background sync with debounce
│
├── Features/                     # Feature modules
│   ├── PatternLock/             # Pattern authentication
│   │   ├── PatternLockView.swift
│   │   ├── PatternGridView.swift
│   │   ├── PatternNode.swift
│   │   └── PatternValidator.swift
│   │
│   ├── VaultViewer/             # File viewing/management
│   │   ├── VaultView.swift
│   │   ├── FileGridView.swift
│   │   ├── SecureImageViewer.swift
│   │   ├── SecureVideoPlayer.swift
│   │   └── FileImporter.swift
│   │
│   ├── Camera/                  # Secure camera
│   │   ├── SecureCameraView.swift
│   │   └── CameraManager.swift
│   │
│   ├── Settings/                # Configuration
│   │   ├── SettingsView.swift   # App-wide settings
│   │   ├── VaultSettingsView.swift  # Per-vault settings
│   │   └── RecoveryPhraseView.swift
│   │
│   ├── Onboarding/              # First-time setup
│   │   ├── OnboardingView.swift
│   │   ├── WelcomeView.swift
│   │   └── PatternSetupView.swift
│   │
│   └── Sharing/                 # Sharing UI
│       ├── ShareVaultView.swift
│       └── JoinVaultView.swift
│
├── Models/                       # Data structures
│   ├── VaultFile.swift
│   └── VaultMetadata.swift
│
└── UI/Components/               # Reusable UI
    ├── LoadingView.swift
    └── SecureTextField.swift
```

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         VaultApp                            │
│                      (AppState singleton)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       ContentView                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Onboarding  │  │ PatternLock │  │     VaultView       │ │
│  │    View     │  │    View     │  │  (authenticated)    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ KeyDerivation │    │ VaultStorage  │    │ CryptoEngine  │
│   (PBKDF2)    │    │  (blob I/O)   │    │  (AES-GCM)    │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│SecureEnclave  │    │  FileSystem   │    │   CryptoKit   │
│  Manager      │    │  (Documents)  │    │               │
└───────────────┘    └───────────────┘    └───────────────┘
```

## AppState

Central state management via `@EnvironmentObject`:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var isUnlocked = false
    @Published var currentVaultKey: Data?
    @Published var showOnboarding = false
    @Published var isLoading = false
    @Published var isSharedVault = false  // true when viewing a received shared vault
}
```

**Key behaviors:**
- `unlockWithPattern(_:gridSize:)` - Derives key, checks duress, sets unlock state, detects shared vaults
- `lockVault()` - Securely clears key from memory, resets state (including `isSharedVault`)
- Always unlocks (even with wrong pattern) - shows empty vault instead of error
- On unlock, checks `index.isSharedVault` and sets `isSharedVault` flag for restricted mode

## Data Flow

### Unlock Flow

```
User draws pattern
        │
        ▼
┌───────────────────────────────────┐
│ PatternSerializer.serialize()     │
│ (pattern + grid size → bytes)     │
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│ SecureEnclaveManager.getDeviceSalt│
│ (device-bound, non-extractable)   │
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│ PBKDF2(pattern, salt, 600k iter)  │
│ → 32-byte vault key               │
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│ DuressHandler.isDuressKey()       │
│ (if duress, destroy other vaults) │
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│ AppState.currentVaultKey = key    │
│ AppState.isUnlocked = true        │
└───────────────────────────────────┘
```

### File Storage Flow

```
User imports file
        │
        ▼
┌───────────────────────────────────┐
│ CryptoEngine.encryptFile()        │
│ - Create header (filename, type)  │
│ - Encrypt header with AES-GCM     │
│ - Encrypt content with AES-GCM    │
│ - Combine: [size][header][content]│
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│ VaultStorage.storeFile()          │
│ - Find next offset in blob        │
│ - Write encrypted data            │
│ - Update encrypted index          │
└───────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────┐
│ vault_data.bin (500MB blob)       │
│ vault_index.bin (encrypted JSON)  │
└───────────────────────────────────┘
```

## Navigation

Uses SwiftUI's `NavigationStack` with type-safe destinations:

```swift
enum VaultSettingsDestination: Hashable {
    case appSettings
    case duressPattern
    case iCloudBackup
    case restoreBackup
    case shareVault
}
```

Sheets used for modal flows (change pattern, share, join).

## Sharing Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Owner Device                                                  │
│                                                               │
│  ShareVaultView ──► CloudKitSharingManager ──► CloudKit      │
│  (policy, phrase)    (chunked upload/download)   (public DB) │
│                                                               │
│  ShareSyncManager ──► Debounce (30s) ──► Upload to all       │
│  (file changes)       active share IDs                        │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ CloudKit Public Database                                      │
│                                                               │
│  SharedVault (manifest) ─── SharedVaultChunk (data, ~50 MB)  │
│  claimed, revoked, policy    chunkData, chunkIndex, vaultId  │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ Recipient Device                                              │
│                                                               │
│  JoinVaultView ──► CloudKitSharingManager ──► Claim + Store  │
│  (enter phrase)    (download, claim)           (local vault)  │
│                                                               │
│  VaultView (restricted mode)                                  │
│  - No add/delete/import                                       │
│  - Screenshot prevention                                      │
│  - Self-destruct checks (expiry, view count, revocation)     │
└──────────────────────────────────────────────────────────────┘
```

## Security Boundaries

| Boundary | Protection |
|----------|------------|
| App ↔ OS | File protection complete, Keychain access control |
| Memory | Keys zeroed on lock, no logging of sensitive data |
| Storage | All data AES-256-GCM encrypted |
| Device | Salt bound to Secure Enclave (non-extractable) |
| Network | Shared vaults encrypted before upload |
| Sharing | One-time phrases, per-recipient revocation |
| Screenshots | Secure text field layer blocks capture |
