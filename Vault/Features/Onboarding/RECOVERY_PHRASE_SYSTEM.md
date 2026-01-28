# Recovery Phrase System - Complete Implementation

## Overview

This document describes the complete recovery phrase system that addresses all the issues with the original implementation and adds new features.

## Problems Solved

### 1. ✅ Recovery phrase changes each time
**Problem:** Each time you opened settings, a new phrase was generated instead of loading the saved one.

**Solution:** Created `RecoveryPhraseManager` that stores and retrieves the actual phrase for each vault.

### 2. ✅ Recovery phrase doesn't work for unlocking
**Problem:** The phrase was generated but the recovery flow couldn't use it to unlock the vault.

**Solution:** Recovery manager stores both:
- The phrase itself (for display)
- A mapping from phrase → vault key (for recovery)

### 3. ✅ No Keychain security
**Problem:** Recovery data was stored in UserDefaults (not secure).

**Solution:** All recovery data is now stored in Keychain with the following security features:
- Single encrypted blob for all vaults (prevents vault enumeration)
- Master key stored separately in Keychain
- File protection: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

### 4. ✅ No custom phrase support
**Problem:** Users could only use auto-generated phrases.

**Solution:** Added full support for custom phrases with:
- Real-time validation
- Entropy checking
- Strength feedback

### 5. ✅ No phrase regeneration
**Problem:** Once set, you couldn't change the recovery phrase.

**Solution:** Added regenerate functionality that:
- Generates a new phrase
- Keeps the same vault key (files remain accessible)
- Shows confirmation warning

## Architecture

### RecoveryPhraseManager (New)

Central manager for all recovery phrase operations:

```swift
// Save during vault creation
try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
    phrase: "the purple elephant dances quietly",
    pattern: [0, 1, 5, 6],
    gridSize: 4,
    patternKey: vaultKey
)

// Load for display in settings
let phrase = try await RecoveryPhraseManager.shared.loadRecoveryPhrase(for: vaultKey)

// Recover vault using phrase
let vaultKey = try await RecoveryPhraseManager.shared.recoverVault(using: userPhrase)

// Regenerate phrase
let newPhrase = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(for: vaultKey)

// Set custom phrase
let newPhrase = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(
    for: vaultKey,
    customPhrase: "my very secure memorable sentence here"
)
```

### Privacy Features

**Single Keychain Entry:**
- Only ONE entry in Keychain regardless of vault count
- Encrypted database contains all vault recovery data
- Impossible to determine number of vaults by inspecting Keychain

**Vault Identification:**
- Uses SHA256 hash of vault key for identification
- No plaintext vault information stored
- Each vault's data is encrypted within the database

**Master Key:**
- Separate master key encrypts the database
- Generated once and stored in Keychain
- Never leaves the device

## Storage Structure

```
Keychain:
├─ "recovery_data" → Encrypted RecoveryDatabase
│   └─ Contains: Array of VaultRecoveryInfo
│       ├─ vaultKeyHash (SHA256)
│       ├─ phrase (encrypted)
│       ├─ pattern (encrypted)
│       ├─ gridSize (encrypted)
│       ├─ patternKey (encrypted)
│       └─ createdAt (encrypted)
│
└─ "recovery_master_key" → Master encryption key
    └─ Used to encrypt/decrypt RecoveryDatabase
```

## User Flows

### 1. Vault Setup (PatternSetupView)
1. User draws pattern twice to confirm
2. **Choice:** Auto-generate or custom phrase
3. If custom: validate strength in real-time
4. Save pattern + phrase to RecoveryPhraseManager
5. Display phrase one time for writing down

### 2. View Recovery Phrase (RecoveryPhraseView)
1. Open vault settings → "View recovery phrase"
2. Load phrase from RecoveryPhraseManager using current vault key
3. Display same phrase every time
4. Option to copy to clipboard (auto-clear after 60s)

### 3. Regenerate Phrase (VaultSettingsView)
1. Open vault settings → "Regenerate recovery phrase"
2. Confirm warning (old phrase stops working)
3. Generate new phrase
4. Save updated recovery data
5. Immediately show new phrase

### 4. Custom Phrase (CustomRecoveryPhraseInputView)
1. Open vault settings → "Set custom recovery phrase"
2. Enter phrase in text editor
3. Real-time validation shows:
   - ✅ Strong (70+ bits entropy)
   - ⚠️ Acceptable (50-70 bits)
   - ❌ Weak (< 50 bits or < 6 words)
4. Save only if acceptable
5. Show success confirmation

### 5. Vault Recovery (RecoveryPhraseInputView)
1. Lock screen → "Use recovery phrase"
2. Enter phrase
3. RecoveryPhraseManager finds matching vault
4. Returns vault key
5. Unlock vault

## Error Handling

### Specific Error Messages

```swift
enum RecoveryError: LocalizedError {
    case invalidPhrase
        → "The recovery phrase you entered is incorrect or doesn't match any vault."
    
    case vaultNotFound
        → "No recovery data found for this vault."
    
    case weakPhrase(message: String)
        → "Your phrase needs at least 6 words with 50+ bits entropy."
    
    case encryptionFailed
        → "Failed to encrypt recovery data."
    
    case keychainError(status: OSStatus)
        → "Keychain error: [code]"
    
    case keyGenerationFailed
        → "Failed to generate encryption key."
}
```

### User-Friendly Fallbacks

- If phrase not found: "No recovery phrase found for this vault"
- If phrase wrong: "Incorrect recovery phrase. Please check and try again."
- If Keychain fails: Falls back to showing specific error code

## Security Considerations

### ✅ What's Protected
- All recovery data encrypted at rest
- Master key never leaves Keychain
- No way to enumerate vaults from outside
- Phrases require decent entropy
- Old phrases invalidated on regeneration

### ⚠️ Limitations
- Custom phrases can be weak if user insists
- Phrases stored on device (not cloud backup)
- If device is erased, recovery phrases lost
- Social engineering still possible

### 🎯 Best Practices
1. Always write down recovery phrase physically
2. Store in secure location (not on device)
3. Test recovery phrase before relying on it
4. Regenerate if phrase is suspected compromised
5. Use auto-generated phrases when possible

## Testing Checklist

### New Vault Setup
- [ ] Auto-generated phrase works
- [ ] Custom phrase validation works
- [ ] Phrase is same when viewed later
- [ ] Phrase can recover vault

### Existing Vault
- [ ] View recovery phrase shows same phrase
- [ ] Regenerate creates new phrase
- [ ] Old phrase stops working
- [ ] New phrase works for recovery
- [ ] Custom phrase can replace generated

### Multiple Vaults
- [ ] Each vault has own phrase
- [ ] Phrases don't interfere
- [ ] Only one Keychain entry exists
- [ ] Recovery finds correct vault

### Edge Cases
- [ ] Empty phrase rejected
- [ ] Very long phrase accepted if strong
- [ ] Special characters handled
- [ ] Case-insensitive matching works
- [ ] Whitespace trimmed properly

## Migration from Old System

If upgrading from the old UserDefaults-based system:

```swift
// TODO: Add migration helper
func migrateOldRecoveryData() async {
    // 1. Check for old "recovery_mapping" in UserDefaults
    // 2. Try to decrypt with various methods
    // 3. Import into RecoveryPhraseManager
    // 4. Delete old UserDefaults entries
    // 5. Log migration success/failure
}
```

## Future Enhancements

### Potential Additions
1. **iCloud Keychain Sync** - Share phrases across user's devices
2. **QR Code Export** - Visual backup of phrase
3. **Biometric Protection** - Require Face/Touch ID to view phrase
4. **Phrase History** - Keep old phrases for limited time
5. **Social Recovery** - Split phrase across trusted contacts
6. **Time-based Expiry** - Force phrase rotation

### Not Recommended
- ❌ Cloud backup of phrases (privacy risk)
- ❌ Email/SMS phrase delivery (insecure)
- ❌ Automatic phrase sharing (defeats purpose)

## Debug Tips

Enable debug logging:
```swift
#if DEBUG
print("📝 [RecoveryManager] Operation details...")
#endif
```

View Keychain entries:
```bash
# On simulator/jailbroken device
security dump-keychain
```

Test phrase strength:
```swift
let validation = RecoveryPhraseGenerator.shared.validatePhrase("your test phrase here")
print(validation.message)
```

## Support

For issues:
1. Check debug logs for error codes
2. Verify Keychain access
3. Test with auto-generated phrase first
4. Ensure vault is unlocked when viewing phrase
5. Try regenerating if phrase seems corrupted
