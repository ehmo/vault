# Vault Sharing

## Overview

Vault sharing uses **one-time phrases** with per-recipient controls. Each share generates a unique phrase that can only be used once. After the recipient claims it, the phrase is burned. The owner can revoke access individually, set expiration dates, limit view counts, and prevent screenshots.

## Model

```
Owner generates share phrase
         │
         ▼
┌─────────────────────────────┐
│ Phrase → SHA256 → vault_id  │  (CloudKit lookup key)
│ Phrase → PBKDF2 → share_key │  (encryption key)
└─────────────────────────────┘
         │
         ▼
Upload encrypted vault chunks + manifest to CloudKit
         │
         ▼
Recipient enters phrase → downloads → phrase burned (claimed=true)
         │
         ▼
Recipient sets local pattern → vault opens in restricted mode
```

### Why One-Time Phrases?

- Owner controls exactly who has access
- Forwarding the phrase is useless after claim
- Individual revocation possible
- Enables per-recipient policies (expiration, view limits)

## Sharing Flow

### Owner: Share Vault

```
Vault Settings → "Share This Vault"
    ↓
┌─────────────────────────────────────┐
│ Share Settings                      │
│                                     │
│ [Toggle] Set expiration date        │
│ [Toggle] Limit number of opens     │
│                                     │
│ Estimated upload: 142 MB            │
│                                     │
│ [Generate Share Phrase]             │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Share phrase (one-time use):        │
│                                     │
│ "The purple elephant dances         │
│  quietly under broken umbrellas"    │
│                                     │
│ [Copy to Clipboard]                 │
│                                     │
│ ⚠ This phrase works once.          │
│ After your recipient uses it,       │
│ it will no longer work.             │
│                                     │
│ Uploading: 3 of 12 chunks... ██░░░  │
└─────────────────────────────────────┘
```

### Owner: Manage Shares

```
Vault Settings → Sharing
├── Shared with 2 people
├── Share #1: Created Jan 28 · Active
│   ├── Expires: Never
│   ├── Last synced: 1h ago
│   └── [Revoke Access]
├── Share #2: Created Jan 29 · Active
│   ├── Expires: Feb 28
│   └── [Revoke Access]
├── [Share with someone new]
└── [Stop All Sharing]
```

### Recipient: Join

```
Lock Screen → "Join shared vault"
    ↓
Enter share phrase → [Join]
    ↓
Downloading vault... (3 of 12 chunks)
    ↓
"Set a pattern to unlock this vault"
    ↓ (draw pattern, confirm)
    ↓
Vault opens (restricted mode)
```

## Architecture

### CloudKit Record Structure

**Manifest record** (`SharedVault`, recordName = SHA256(phrase)):
```
shareVaultId: String           // unique ID for this share
updatedAt: Date
version: Int
ownerFingerprint: String
chunkCount: Int
claimed: Bool                  // true after first download
revoked: Bool                  // owner sets true to revoke
policy: CKAsset               // encrypted SharePolicy
```

**Chunk records** (`SharedVaultChunk`, recordName = "{shareVaultId}_chunk_{index}"):
```
chunkData: CKAsset             // encrypted file data (~50 MB)
chunkIndex: Int
vaultId: String                // reference to parent shareVaultId
```

### Claiming Flow

1. Recipient downloads vault → sets `claimed = true` on manifest
2. Subsequent attempts see `claimed = true` → rejected with "already used" error
3. Owner generates new shareVaultId for each recipient

### Chunked Uploads

- Files packed into chunks (~50 MB each)
- Uploaded sequentially with progress tracking
- Sync updates delete old chunks, upload new ones
- Overcomes CloudKit's 250 MB asset limit

### Multi-Recipient Sync

- Owner tracks all active share IDs in `VaultIndex.activeShares`
- `ShareSyncManager` debounces file changes (30s) then syncs to all share IDs
- Each share has its own encryption key derived from vault key + share ID

## Share Policy

```swift
struct SharePolicy: Codable {
    var expiresAt: Date?           // nil = never
    var maxOpens: Int?             // nil = unlimited
    var allowScreenshots: Bool     // default false
}
```

Policies are encrypted and stored as a CloudKit asset on the manifest record.

## Recipient Restrictions

### Restricted Mode

When `isSharedVault == true`, VaultView enforces:
- No camera, import, or delete buttons
- No share sheet on files
- "Shared Vault" banner with expiry info
- Auto-check for updates on open

### Screenshot Prevention

Uses the `UITextField.isSecureTextEntry` trick:
- Hidden UITextField with `isSecureTextEntry = true`
- Vault content placed in its layer hierarchy
- iOS blocks screen capture/recording of secure text fields
- Content appears black in screenshots and screen recordings

### Self-Destruct

On each shared vault open, checks:
1. `sharePolicy.expiresAt` → if past, delete local vault data
2. Increment `openCount` vs `sharePolicy.maxOpens` → if exceeded, delete
3. CloudKit manifest for `revoked == true` → if revoked, delete

On destruct: overwrite blob region with random data, delete index entry, lock vault.

## VaultIndex Sharing Fields

```swift
// Owner side
var activeShares: [ShareRecord]?   // nil = not shared

struct ShareRecord: Codable, Identifiable {
    let id: String                 // share vault ID
    let createdAt: Date
    let policy: SharePolicy
    var lastSyncedAt: Date?
}

// Recipient side
var isSharedVault: Bool?
var sharedVaultId: String?         // for update checks
var sharePolicy: SharePolicy?      // restrictions set by owner
var openCount: Int?                // track opens for maxOpens
```

## Key Derivation

### Phrase → Lookup ID

```swift
SHA256(normalizedPhrase).prefix(16).hex  // 32 hex chars
```

### Phrase → Encryption Key

```swift
PBKDF2(normalizedPhrase, salt: "vault-share-v1-salt", iterations: 800_000, keyLength: 32)
```

Fixed salt so the same phrase produces the same key on any device.

### Per-Share Sync Key

For background sync, each share gets a unique key:
```swift
SHA256(vaultKey + shareId)  // 32 bytes
```

This lets the owner encrypt differently per recipient without storing the original phrase.

## Implementation Files

| File | Purpose |
|------|---------|
| `CloudKitSharingManager.swift` | Chunked upload/download, claim, revoke, update check |
| `ShareSyncManager.swift` | Background sync with debounce, multi-target upload |
| `ShareVaultView.swift` | Policy config, phrase gen, manage shares, revoke |
| `JoinVaultView.swift` | Claim flow, download progress, pattern setup |
| `VaultView.swift` | Restricted mode, screenshot block, self-destruct checks |
| `VaultStorage.swift` | ShareRecord, SharePolicy, VaultIndex sharing fields |
| `KeyDerivation.swift` | `deriveShareKey()`, `shareVaultId()` |

## Error Handling

| Error | User Message |
|-------|--------------|
| `vaultNotFound` | "No vault found with this phrase" |
| `alreadyClaimed` | "This share phrase has already been used" |
| `decryptionFailed` | "Could not decrypt. Check phrase." |
| `revoked` | "Access to this vault has been revoked" |
| `uploadFailed` | "Upload failed. Try again." |
| `notAvailable` | "iCloud not available" |

## Security Considerations

### One-Time Phrases

- Each phrase can only be claimed once
- After claim, `claimed=true` is set on the CloudKit manifest
- Forwarding the phrase after claim is useless

### Revocation

- Owner can revoke individual shares
- Revocation sets `revoked=true` on the CloudKit manifest
- Recipient sees "Access revoked" on next vault open
- Local data is deleted on revocation detection

### Client-Side Enforcement

Screenshot prevention, expiration, and view limits are enforced client-side. This is "DRM-lite" - it prevents casual copying but a determined attacker with a jailbroken device could bypass these controls. The encryption itself remains the primary security layer.

### Plausible Deniability

Sharing reduces plausible deniability:
- Recipient knows the vault exists
- Recipient can prove content was shared
- CloudKit records exist (encrypted, but present)

## Testing Checklist

1. [ ] Owner shares vault → gets one-time phrase → upload starts
2. [ ] Recipient enters phrase → downloads vault → phrase is burned
3. [ ] Third party tries same phrase → "This phrase has already been used"
4. [ ] Recipient sets pattern → opens vault in restricted mode
5. [ ] Screenshot attempt → screen goes black in capture
6. [ ] Owner adds file → auto-syncs (30s debounce) to all share IDs
7. [ ] Recipient opens vault → auto-check → "New files available" banner
8. [ ] Owner shares with second person → new phrase → both get updates
9. [ ] Owner revokes share #1 → recipient #1 sees "Access revoked", data deleted
10. [ ] Expiration date passes → recipient sees "Vault expired", data deleted
11. [ ] Owner stops all sharing → all CloudKit records deleted
