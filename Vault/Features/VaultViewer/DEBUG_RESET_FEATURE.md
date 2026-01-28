# Debug Reset Feature Documentation

## Overview

A comprehensive debug-only reset/wipe feature has been added to the App Settings to help with development and testing. This feature is **only available in DEBUG builds** and will not appear in production/release builds.

## Location

**App Settings** → **Debug Tools** section (at the bottom, above "Danger Zone")

## Features

### 1. Reset Onboarding (Existing)
- Resets the onboarding flag
- Shows the onboarding flow again on next launch
- **Does NOT** delete any vault data

### 2. Full Reset / Wipe Everything (NEW) 🆕
A complete factory reset that wipes:
- ✅ All vault files and storage directories
- ✅ Recovery phrase mappings (encrypted backups)
- ✅ All UserDefaults preferences
- ✅ All Keychain entries (encryption keys, salts)
- ✅ Temporary files
- ✅ Onboarding state

## How It Works

### The Wipe Process

```
User taps "Full Reset / Wipe Everything"
           ↓
Confirmation alert appears with detailed list
           ↓
User confirms "Wipe Everything"
           ↓
Sequential cleanup begins:

1️⃣  Clear vault storage directory
    └─ Deletes all encrypted vault files

2️⃣  Clear recovery mappings
    └─ Removes recovery phrase encryption mapping

3️⃣  Clear UserDefaults
    └─ Removes all app preferences and settings

4️⃣  Clear Keychain
    └─ Removes all secure storage items
       (passwords, keys, certificates, identities)

5️⃣  Clear temporary files
    └─ Removes decrypted video/image temp files

6️⃣  Reset app state
    └─ Locks vault and triggers onboarding
```

## Security Considerations

### ✅ Safe for Development
- Only compiled in DEBUG builds
- Uses `#if DEBUG` compiler directives
- Will not exist in production builds

### ⚠️ Data Loss Warning
The confirmation alert clearly states:
> "This will completely wipe:
> • All vault files and indexes
> • Recovery phrase mappings
> • User preferences
> • Keychain entries
> • Onboarding state
> 
> The app will restart as if freshly installed."

## Implementation Details

### Files Modified
- `SettingsView.swift`

### Key Functions
```swift
performDebugFullReset() -> void
    ├─ debugFullReset() -> async
    │   ├─ clearVaultStorage() -> async
    │   ├─ clearRecoveryMappings()
    │   ├─ clearUserDefaults()
    │   ├─ clearKeychain()
    │   ├─ clearTemporaryFiles()
    │   └─ appState.resetToOnboarding()
```

### Cleared Keychain Classes
- `kSecClassGenericPassword` - Generic passwords
- `kSecClassInternetPassword` - Internet passwords
- `kSecClassCertificate` - Certificates
- `kSecClassKey` - Cryptographic keys
- `kSecClassIdentity` - Identities

## Testing Scenarios

### Use Cases
1. **Testing fresh installs** - Simulate a brand new app installation
2. **Testing onboarding** - Reset to see the onboarding flow
3. **Clearing test data** - Remove test vaults and files
4. **Debugging encryption** - Clear corrupted encryption states
5. **Testing recovery phrases** - Start fresh with new patterns

### Before Each Test
1. Go to Settings
2. Scroll to "Debug Tools" (orange hammer icon)
3. Tap "Full Reset / Wipe Everything"
4. Confirm the action
5. App returns to onboarding state

## Comparison with Nuclear Option

| Feature | Debug Reset | Nuclear Option (Production) |
|---------|-------------|------------------------------|
| **Availability** | DEBUG only | All builds |
| **Vault files** | ✅ Deleted | ✅ Destroyed |
| **Recovery mappings** | ✅ Cleared | ❌ Not cleared |
| **UserDefaults** | ✅ Full domain clear | ❌ Partial |
| **Keychain** | ✅ All items cleared | ❌ Selective |
| **Temp files** | ✅ Cleared | ❌ Not cleared |
| **Purpose** | Development testing | Emergency data destruction |

## Example Console Output

```
🧹 [Debug] Starting full reset...
🧹 [Debug] Vault storage cleared
🧹 [Debug] Recovery mappings cleared
🧹 [Debug] UserDefaults cleared
🧹 [Debug] Keychain cleared
🧹 [Debug] Temporary files cleared
✅ [Debug] Full reset complete!
🔒 [AppState] lockVault() called
🔄 [AppState] Reset to onboarding state
```

## User Interface

### Debug Tools Section
```
┌─────────────────────────────────────────┐
│ 🔨 Debug Tools                          │
├─────────────────────────────────────────┤
│ 🔄 Reset Onboarding                     │
│ 🗑️ Full Reset / Wipe Everything         │
├─────────────────────────────────────────┤
│ Development only: Reset onboarding or   │
│ completely wipe all data including      │
│ vault files, recovery phrases,          │
│ settings, and Keychain entries.         │
└─────────────────────────────────────────┘
```

### Confirmation Alert
```
┌─────────────────────────────────────────┐
│        Debug: Full Reset                │
├─────────────────────────────────────────┤
│ This will completely wipe:              │
│ • All vault files and indexes           │
│ • Recovery phrase mappings              │
│ • User preferences                      │
│ • Keychain entries                      │
│ • Onboarding state                      │
│                                         │
│ The app will restart as if freshly      │
│ installed.                              │
├─────────────────────────────────────────┤
│           [Cancel] [Wipe Everything]    │
└─────────────────────────────────────────┘
```

## Best Practices

### When to Use
- ✅ Between major test iterations
- ✅ When testing new encryption implementations
- ✅ When debugging pattern/recovery issues
- ✅ Before testing the onboarding flow
- ✅ When vault state becomes corrupted

### When NOT to Use
- ❌ During active debugging (will lose current state)
- ❌ If you need to preserve test vaults
- ❌ In production builds (feature won't exist)

## Notes

- The feature is **async** to handle file operations properly
- All operations are wrapped in `#if DEBUG` checks
- Console logging helps track the reset progress
- UserDefaults synchronization ensures immediate persistence
- Keychain clearing covers all security item classes
- Temporary directory is fully cleared of decrypted files

## Related Features

- **Reset Onboarding**: Lighter reset, only affects onboarding flag
- **Nuclear Option**: Production emergency wipe (less comprehensive)
- **Recovery Phrases**: Now properly stored and can be fully reset

---

**Version**: 1.0.0  
**Last Updated**: January 27, 2026  
**Build Configuration**: DEBUG Only
