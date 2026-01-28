# Vault Sharing

## Overview

Vault sharing allows users to share a vault with others using a memorable phrase. The phrase serves dual purposes:
1. **Identifies** the vault in CloudKit (via hash)
2. **Decrypts** the vault contents (via key derivation)

No accounts, no friend requests, no QR codes. Just a phrase.

## How It Works

### The Phrase Does Everything

```
Share phrase: "The purple elephant dances quietly under broken umbrellas"
                    │
         ┌─────────┴─────────┐
         │                   │
         ▼                   ▼
   SHA256(phrase)      PBKDF2(phrase)
   = vault_id          = encryption_key
         │                   │
         ▼                   ▼
   Find in iCloud      Decrypt contents
```

### Sharing Flow

**User A (owner):**
```
1. Open vault → Settings → Share This Vault
2. App generates memorable phrase
3. App uploads encrypted vault to CloudKit
4. User A sends phrase to User B (any channel)
```

**User B (recipient):**
```
1. Open app → "Join shared vault"
2. Enter the phrase
3. App downloads from CloudKit
4. App decrypts and imports files
5. Vault appears with same content
```

## Architecture

### CloudKit Public Database

Shared vaults use CloudKit's **public database** - accessible by all users of the app:

```
┌─────────────────────────────────────────┐
│      CloudKit Public Database           │
│   (shared by all Vault app users)       │
│                                         │
│  Record: vault_id → encrypted_blob      │
│  Record: vault_id → encrypted_blob      │
│  ...                                    │
└─────────────────────────────────────────┘
         ↑                    ↑
      User A              User B
   (uploads)           (downloads)
```

**Why public database is secure:**
- `vault_id` = SHA256(phrase) - unguessable without phrase
- Contents encrypted with PBKDF2(phrase)
- Anyone *could* fetch a record, but can't decrypt without phrase
- No metadata links vault to any user identity

### Data Structure

```swift
struct SharedVaultData: Codable {
    let files: [SharedFile]
    let metadata: SharedVaultMetadata
    let createdAt: Date
    let updatedAt: Date
}

struct SharedFile: Codable {
    let id: UUID
    let filename: String
    let mimeType: String
    let size: Int
    let encryptedContent: Data  // Re-encrypted with share key
    let createdAt: Date
}

struct SharedVaultMetadata: Codable {
    let ownerFingerprint: String
    let sharedAt: Date
}
```

### CloudKit Record

```swift
let record = CKRecord(recordType: "SharedVault")
record["encryptedData"] = CKAsset(fileURL: tempURL)  // Encrypted blob
record["updatedAt"] = Date()
record["version"] = 1
```

## Key Derivation

### Why Fixed Salt?

Unlike local vaults (which use device-bound salt), share keys use a **fixed salt**:

```swift
let salt = "vault-share-v1-salt".data(using: .utf8)!
```

**Reason:** The same phrase must produce the same key on ANY device. Device-bound salt would make sharing impossible.

**Security:** Relies entirely on phrase entropy (~80+ bits from RecoveryPhraseGenerator).

### Derivation Process

```swift
static func deriveShareKey(from phrase: String) throws -> Data {
    let normalized = phrase
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return PBKDF2(
        password: normalized,
        salt: "vault-share-v1-salt",
        iterations: 800_000,
        keyLength: 32
    )
}
```

### Vault ID Generation

```swift
static func vaultId(from phrase: String) -> String {
    let normalized = normalizePhrase(phrase)
    let hash = SHA256.hash(data: normalized.data(using: .utf8)!)
    return hash.prefix(16).hexString  // 32 hex chars
}
```

## Phrase Generation

Uses `RecoveryPhraseGenerator` with templates for memorable sentences:

**Templates:**
- "The [adjective] [noun] [verb] [adverb] [preposition] the [adjective] [noun]"
- "[Number] [adjective] [plural noun] [past verb] [adverb] [preposition] [possessive] [noun]"

**Example outputs:**
- "The purple elephant dances quietly under the broken umbrella"
- "Seven hungry cats waited patiently outside her grandmother's bakery"
- "My favorite uncle sleeps peacefully beside the ancient lighthouse"

**Entropy:** ~80-90 bits (depending on word list sizes)

## Security Considerations

### Phrase Is The Secret

- Anyone with the phrase has **full access**
- Can view, add, and delete files
- No permission levels (read-only not supported)

### No Revocation

Once shared, you cannot kick someone out:
- They have the phrase
- Can always derive the key
- Can always access the vault

**Workaround:** Create new vault, share new phrase, don't share with unwanted person.

### Plausible Deniability Lost

Sharing a vault means:
- Recipient knows the vault exists
- Recipient can prove you had this content
- Local plausible deniability doesn't extend to shared vaults

### iCloud Requirement

Both users need:
- iCloud account signed in
- iCloud Drive enabled
- Network connectivity

### Phrase Transmission

The phrase must be sent via some channel:
- In person (most secure)
- Encrypted messaging
- NOT plain SMS/email (can be intercepted)

## Implementation Files

| File | Purpose |
|------|---------|
| `CloudKitSharingManager.swift` | CloudKit operations, key derivation |
| `ShareVaultView.swift` | UI for sharing a vault |
| `JoinVaultView.swift` | UI for joining a shared vault |
| `KeyDerivation.swift` | `deriveShareKey()`, `shareVaultId()` |

## User Interface

### Sharing (Owner)

```
┌─────────────────────────────┐
│  Share Vault                │
├─────────────────────────────┤
│                             │
│  Share phrase:              │
│                             │
│  "The purple elephant       │
│   dances quietly under      │
│   broken umbrellas"         │
│                             │
│  [Copy to Clipboard]        │
│                             │
│  ⚠️ Important               │
│  Anyone with this phrase    │
│  has full access.           │
│                             │
│  [Upload & Share]           │
│                             │
└─────────────────────────────┘
```

### Joining (Recipient)

```
┌─────────────────────────────┐
│  Join Shared Vault          │
├─────────────────────────────┤
│                             │
│  Enter share phrase:        │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  [Join Vault]               │
│                             │
│  ℹ️ How it works            │
│  The phrase identifies and  │
│  decrypts the shared vault. │
│                             │
└─────────────────────────────┘
```

## Sync (Future Enhancement)

Current implementation: **One-time import**

Files are downloaded and imported to local storage. Changes don't sync automatically.

**Future enhancement options:**
1. **Pull-to-refresh** - Manual sync
2. **Background sync** - Periodic CloudKit checks
3. **Push notifications** - CKSubscription for changes
4. **Conflict resolution** - Last-write-wins or merge

## Error Handling

| Error | User Message |
|-------|--------------|
| `vaultNotFound` | "No vault found with this phrase" |
| `decryptionFailed` | "Could not decrypt. Check phrase." |
| `uploadFailed` | "Upload failed. Try again." |
| `notAvailable` | "iCloud not available" |

## Testing Checklist

1. [ ] User A creates vault with pattern, adds files
2. [ ] User A taps Share → gets phrase
3. [ ] User A sends phrase to User B
4. [ ] User B opens Vault app → Join Shared Vault
5. [ ] User B enters phrase → sees same files
6. [ ] Verify phrase case-insensitivity
7. [ ] Verify extra whitespace is normalized
8. [ ] Test with no iCloud → appropriate error
9. [ ] Test with wrong phrase → "not found" error
