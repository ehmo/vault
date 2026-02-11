# Recovery Phrase - Quick Start Guide

## For Users

### Setting Up Your Vault
1. Draw your unlock pattern twice
2. Choose **Auto-Generate** or **Custom Phrase**
3. **Write down your recovery phrase** on paper
4. Store it somewhere safe (not on your device!)
5. Tap "I've Saved It" to continue

### Viewing Your Recovery Phrase
1. Open vault → Settings ⚙️
2. Tap "View recovery phrase"
3. Tap to reveal the phrase
4. Copy or write it down again if needed

### Using Recovery Phrase
1. On lock screen → "Use recovery phrase"
2. Type your full recovery phrase
3. Tap "Recover Vault"
4. Your vault unlocks without the pattern!

### Changing Your Recovery Phrase

**Auto-Generate New One:**
1. Vault Settings → "Regenerate recovery phrase"
2. Confirm warning ⚠️
3. Write down the NEW phrase
4. Old phrase no longer works

**Set Custom Phrase:**
1. Vault Settings → "Set custom recovery phrase"
2. Type your memorable sentence
3. Check that it's marked as ✅ Acceptable or Strong
4. Tap "Set Custom Phrase"
5. Write it down!

---

## For Developers

### Quick Integration

```swift
// 1. Save during vault setup
try await RecoveryPhraseManager.shared.saveRecoveryPhrase(
    phrase: generatedOrCustomPhrase,
    pattern: patternArray,
    gridSize: 4,
    patternKey: vaultKey
)

// 2. Load for display
let phrase = try await RecoveryPhraseManager.shared.loadRecoveryPhrase(for: vaultKey)

// 3. Recover vault
let recoveredKey = try await RecoveryPhraseManager.shared.recoverVault(using: userPhrase)

// 4. Regenerate
let newPhrase = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(for: vaultKey)

// 5. Set custom
let customPhrase = try await RecoveryPhraseManager.shared.regenerateRecoveryPhrase(
    for: vaultKey, 
    customPhrase: userInput
)
```

### Key Files Modified

| File | Changes |
|------|---------|
| `RecoveryPhraseManager.swift` | **NEW** - Central recovery system |
| `PatternSetupView.swift` | Added custom phrase UI + validation |
| `RecoveryPhraseView.swift` | Now loads from manager (same phrase) |
| `PatternLockView.swift` | Uses manager for recovery |
| `VaultSettingsView.swift` | Added regenerate + custom buttons |

### Privacy Guarantees

✅ **One Keychain entry** - Can't tell how many vaults exist  
✅ **Encrypted database** - All phrases encrypted at rest  
✅ **No cloud sync** - Everything local only  
✅ **Master key** - Separate encryption layer  

### Error Codes

```swift
catch RecoveryError.invalidPhrase {
    // User typed wrong phrase
}
catch RecoveryError.vaultNotFound {
    // No recovery data for this vault
}
catch RecoveryError.weakPhrase(let msg) {
    // Custom phrase too weak
}
catch RecoveryError.keychainError(let status) {
    // Keychain access failed
}
```

### Testing Scenarios

```swift
// Test phrase validation
let validation = RecoveryPhraseGenerator.shared.validatePhrase("test phrase here")
assert(validation.isAcceptable)

// Test full flow
let phrase = "the purple elephant dances quietly"
try await manager.saveRecoveryPhrase(phrase: phrase, pattern: [0,1,5,6], gridSize: 4, patternKey: key)
let loaded = try await manager.loadRecoveryPhrase(for: key)
assert(loaded == phrase)
let recovered = try await manager.recoverVault(using: phrase)
assert(recovered == key)
```

### Common Pitfalls

❌ **Don't** store phrases in UserDefaults  
❌ **Don't** generate new phrases each time  
❌ **Don't** forget to trim whitespace  
❌ **Don't** allow weak custom phrases without warning  

✅ **Do** use RecoveryPhraseManager for all operations  
✅ **Do** validate custom phrases  
✅ **Do** show the phrase immediately after creation  
✅ **Do** warn users before regenerating  

---

## FAQ

**Q: What happens if I regenerate my recovery phrase?**  
A: Your old phrase immediately stops working. You must write down the new phrase.

**Q: Can I have the same recovery phrase for multiple vaults?**  
A: No. Each vault gets a unique phrase for security.

**Q: What if I forget both my pattern AND recovery phrase?**  
A: Your vault is permanently locked. There's no backdoor by design.

**Q: How strong should my custom phrase be?**  
A: Aim for 70+ bits of entropy. Use 6-9 words with mix of common/uncommon.

**Q: Can someone steal my phrases from Keychain?**  
A: Only with physical device access + your device passcode. Keep device secure.

**Q: Do phrases sync via iCloud?**  
A: No. Phrases are device-only for maximum privacy.

**Q: Can I export my recovery phrase?**  
A: Yes - tap "Copy to Clipboard" when viewing it. Auto-clears after 60s.

**Q: How many vaults can an attacker tell I have?**  
A: Zero. There's only one Keychain entry regardless of vault count.

---

## Support

Issues? Check:
1. Debug logs (`#if DEBUG` blocks)
2. Keychain permissions
3. Device lock settings
4. Phrase format (no extra spaces?)

Still stuck? See `RECOVERY_PHRASE_SYSTEM.md` for detailed architecture.
