# Security Model

## Overview

Vault uses defense-in-depth with multiple layers of protection:

1. **Encryption** - AES-256-GCM for all data at rest
2. **Key Derivation** - PBKDF2 with device-bound salt
3. **Plausible Deniability** - No way to prove vault existence
4. **Duress Protection** - Emergency destruction mechanism
5. **Memory Security** - Keys cleared on lock

## Key Derivation

### Pattern-Based Keys (Local Vaults)

```
Pattern + Grid Size
        │
        ▼
┌─────────────────────────────────┐
│ PatternSerializer               │
│ - Encode pattern as bytes       │
│ - Include grid size in hash     │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│ Secure Enclave Salt             │
│ - 32 bytes, device-bound        │
│ - Non-extractable               │
│ - Unique per device             │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│ PBKDF2-HMAC-SHA512              │
│ - 600,000 iterations            │
│ - 32-byte output                │
└─────────────────────────────────┘
        │
        ▼
    Vault Key (AES-256)
```

**Why device-bound salt?**
- Same pattern produces different keys on different devices
- Prevents offline brute-force if device storage is copied
- Attacker must have physical device to attempt unlock

### Recovery Phrase Keys

```
Recovery Phrase
        │
        ▼
┌─────────────────────────────────┐
│ Normalize                       │
│ - Lowercase                     │
│ - Trim whitespace               │
│ - Single space between words    │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│ PBKDF2-HMAC-SHA512              │
│ - Device-bound salt             │
│ - 800,000 iterations            │
│ - 32-byte output                │
└─────────────────────────────────┘
        │
        ▼
    Vault Key (AES-256)
```

**Higher iterations** because phrases have more entropy but are slower to type (timing attack mitigation less critical).

### Share Keys (Device-Independent)

```
Share Phrase
        │
        ▼
┌─────────────────────────────────┐
│ Normalize (same as recovery)    │
└─────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────┐
│ PBKDF2-HMAC-SHA512              │
│ - FIXED salt: "vault-share-v1"  │
│ - 800,000 iterations            │
│ - 32-byte output                │
└─────────────────────────────────┘
        │
        ▼
    Share Key (AES-256)
```

**Why fixed salt?**
- Share keys must be derivable on ANY device
- Same phrase → same key everywhere
- Security relies on phrase entropy (~80+ bits)

### Per-Share Sync Keys

For background sync after initial share, each share gets a unique key derived without storing the original phrase:

```
Vault Key + Share ID
        │
        ▼
┌─────────────────────────────────┐
│ SHA256(vaultKey + shareId)       │
│ → 32-byte share sync key        │
└─────────────────────────────────┘
```

**Why separate key?**
- Owner doesn't store original share phrases
- Each recipient gets uniquely encrypted data
- Owner can always regenerate from vault key + stored share ID

## Encryption

### Algorithm: AES-256-GCM

- **Key size**: 256 bits
- **Nonce**: 12 bytes, randomly generated per encryption
- **Authentication**: Built-in (GCM mode)
- **Output**: nonce + ciphertext + auth tag (combined)

### File Encryption Format

```
┌────────────────────────────────────────────────────────────┐
│ 4 bytes: Encrypted header size                             │
├────────────────────────────────────────────────────────────┤
│ Variable: Encrypted header (AES-256-GCM)                   │
│   ├─ File ID (UUID)                                        │
│   ├─ Original filename                                     │
│   ├─ MIME type                                             │
│   ├─ Original size                                         │
│   └─ Created timestamp                                     │
├────────────────────────────────────────────────────────────┤
│ Variable: Encrypted content (AES-256-GCM)                  │
└────────────────────────────────────────────────────────────┘
```

### Index Encryption

The vault index (file list + offsets) is encrypted separately:

```swift
struct VaultIndex: Codable {
    var files: [VaultFileEntry]
    var nextOffset: Int
    var totalSize: Int
}
```

- Encrypted with same vault key
- Stored in `vault_index.bin`
- Decryption failure → empty vault (not error)

## Plausible Deniability

### The Problem

Traditional encrypted vaults are obvious targets. An attacker knows:
- A vault exists
- Approximately how much data it contains
- That you're hiding something

### The Solution

**Pre-allocated Random Blob**

```
vault_data.bin (500 MB)
┌─────────────────────────────────────────────────────────────┐
│ Random data (indistinguishable from encrypted data)         │
│                                                             │
│   [Encrypted file 1]                                        │
│   [Encrypted file 2]                                        │
│   [Random padding...]                                       │
│   [More random data...]                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Properties:**
- Blob created on first launch, filled with random data
- Files written at specific offsets
- Deleted files overwritten with random data
- Statistical analysis cannot distinguish data from noise
- No metadata reveals file count or sizes

### Wrong Pattern Behavior

**Critical design decision**: Wrong patterns show empty vault, not error.

```
Correct pattern → Decrypts index → Shows files
Wrong pattern  → Decryption fails → Shows empty vault
No pattern     → Shows empty vault
```

This means:
- Attacker cannot know if pattern is wrong or vault is empty
- Brute-force provides no feedback
- User under coercion can claim vault is empty

## Duress Protection

### Concept

A "duress vault" can be designated. When its pattern is entered:
1. All OTHER vaults are silently destroyed
2. The duress vault opens normally
3. No visible indication anything happened

### Use Case

User forced to unlock phone:
1. Enter duress pattern
2. Show innocent-looking duress vault
3. Sensitive vaults permanently destroyed
4. Attacker sees normal vault, believes that's all there is

### Implementation

```swift
// On unlock
if await DuressHandler.shared.isDuressKey(key) {
    await DuressHandler.shared.triggerDuress(preservingKey: key)
}
// Then continue normal unlock...
```

`triggerDuress`:
1. Overwrites entire blob with random data
2. Deletes all index files
3. Recreates empty blob
4. Preserves only the duress vault's data

## Timing Attack Mitigation

### Problem

If unlock is faster for wrong patterns, attacker can detect correct pattern.

### Solution

```swift
// Always delay 1-2 seconds (random)
let delay = Double.random(in: 1.0...2.0)
try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
```

All unlock attempts take the same time regardless of:
- Pattern length
- Whether pattern matches a vault
- Whether duress was triggered

## Memory Security

### Key Handling

```swift
func lockVault() {
    // Securely clear the key from memory
    if var key = currentVaultKey {
        key.resetBytes(in: 0..<key.count)
    }
    currentVaultKey = nil
    isUnlocked = false
}
```

### Automatic Lock

App locks immediately when:
- App goes to background
- Screen recording detected
- User taps lock button

## Threat Model

### Protected Against

| Threat | Mitigation |
|--------|------------|
| Device theft | Device-bound salt, file protection |
| Brute force | 600k PBKDF2 iterations, no timing leak |
| Forensic analysis | Plausible deniability, random blob |
| Coercion | Duress vault, empty vault on wrong pattern |
| Memory dump | Keys cleared on lock |
| Network sniffing | Share data encrypted before upload |
| Phrase forwarding | One-time claim, phrase burned after use |
| Unauthorized access | Per-recipient revocation |
| Screenshots | UITextField.isSecureTextEntry layer trick |

### Not Protected Against

| Threat | Reason |
|--------|--------|
| Compromised device | Root access can intercept keys |
| Keylogger | Pattern can be captured |
| Shoulder surfing | Visual pattern entry |
| $5 wrench attack | Physical coercion beyond duress |
| State-level adversary | May have device exploits |

## Screenshot Prevention

When `isSharedVault == true` and `sharePolicy.allowScreenshots == false`, VaultView applies screenshot prevention:

```
┌─────────────────────────────────┐
│ Hidden UITextField              │
│   isSecureTextEntry = true      │
│   ┌─────────────────────────┐   │
│   │ Vault content placed    │   │
│   │ in its layer hierarchy  │   │
│   └─────────────────────────┘   │
└─────────────────────────────────┘
```

iOS automatically blocks screen capture/recording of secure text field content. In screenshots and screen recordings, the vault content appears black.

**Limitations (DRM-lite):**
- Client-side enforcement only
- Jailbroken devices can bypass
- Prevents casual copying, not determined attackers
- Encryption remains the primary security layer

## Security Recommendations

1. **Use long patterns** - Minimum 6 nodes, prefer 8+
2. **Don't reuse patterns** - Each vault should have unique pattern
3. **Enable auto-wipe** - Configurable failed attempt threshold
4. **Set up duress vault** - Even if empty, provides plausible cover
5. **Use random grid** - Defeats smudge attacks
6. **Regular backups** - Duress destruction is permanent
