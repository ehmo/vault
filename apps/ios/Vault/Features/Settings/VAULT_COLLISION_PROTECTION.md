# Vault Collision Protection

## Overview

The vault system now includes protection against accidentally creating or changing to a pattern that's already used by another vault. This prevents data loss from vault index file collisions.

## The Problem

Since vault index files are named based on a hash of the encryption key:
```
vault_index_<SHA256_hash>.bin
```

If two patterns derive to the same key (extremely unlikely) or if a user reuses the same pattern:
- Creating a new vault with an existing pattern would **overwrite** the old vault's index
- Changing to an existing pattern would **destroy** the original vault
- Users would lose access to their data without warning

## The Solution

### 1. Detection

Added `vaultExists(for:)` method to VaultStorage:
```swift
func vaultExists(for key: Data) -> Bool {
    let indexURL = indexURL(for: key)
    return fileManager.fileExists(atPath: indexURL.path)
}
```

This checks if a vault index file already exists for a given key.

### 2. Protection During Vault Creation

In `PatternSetupView.savePattern()`:
```swift
// Check if a vault already exists with this pattern
if VaultStorage.shared.vaultExists(for: key) {
    // Show error and return to pattern creation
    validationResult = PatternValidationResult(
        isValid: false,
        errors: [.custom("This pattern is already used by another vault...")],
        ...
    )
    return
}
```

**User Experience:**
- User creates and confirms a pattern
- System detects it matches an existing vault
- User is returned to the "Create Pattern" step
- Error message shown: "This pattern is already used by another vault. Please choose a different pattern."
- User can try a different pattern

### 3. Protection During Pattern Change

In `VaultStorage.changeVaultKey()`:
```swift
// Check if new key would overwrite an existing vault
if vaultExists(for: newKey) {
    throw VaultStorageError.vaultAlreadyExists
}
```

In `VaultSettingsView.updateVaultPattern()`:
```swift
catch VaultStorageError.vaultAlreadyExists {
    errorMessage = "This pattern is already used by another vault..."
    step = .createNew  // Return to new pattern creation
    newPattern = []
    patternState.reset()
}
```

**User Experience:**
- User changes pattern through settings
- Verifies current pattern ✓
- Creates new pattern ✓
- Confirms new pattern ✓
- System detects collision
- User returns to "Create New Pattern" step
- Error message shown
- User can try a different pattern

## Error Handling

### New Error Type

Added to `VaultStorageError`:
```swift
enum VaultStorageError: Error {
    ...
    case vaultAlreadyExists
}
```

### Custom Validation Error

Updated `PatternValidationError` to support custom messages:
```swift
enum PatternValidationError: String {
    case tooFewNodes = "..."
    case tooFewDirectionChanges = "..."
    case custom(String)  // ← New
    
    var rawValue: String {
        switch self {
        case .custom(let message):
            return message
        ...
        }
    }
}
```

## Edge Cases

### Case 1: Same Pattern, Different Grid Size
**Scenario:** User creates pattern A on 4×4 grid, then creates same pattern on 5×5 grid

**Result:** Different keys are derived (grid size affects key derivation), so no collision occurs. These are treated as separate vaults.

### Case 2: Collision During Pattern Change
**Scenario:** User has Vault A (pattern X) and Vault B (pattern Y), tries to change Vault A to pattern Y

**Protected:** System detects collision, prevents change, returns user to pattern creation

### Case 3: Key Collision (Theoretical)
**Scenario:** Two different patterns somehow derive to the same 256-bit key

**Probability:** ~1 in 2^256 (astronomically unlikely)

**Protected:** Same mechanism catches this

### Case 4: Multiple Simultaneous Vaults
**Scenario:** User has 3 vaults with different patterns

**Behavior:** All protected independently. Can't create/change to any existing pattern.

## Security Implications

### Privacy
- Collision check reveals that a pattern is "taken" but not what data is in that vault
- An attacker could theoretically enumerate patterns to find used ones
- However, they still need to break Argon2 key derivation to access data

### Data Protection
- Prevents accidental data loss from vault overwrites
- Maintains vault isolation (can't merge vaults accidentally)
- No single point of failure

## User Messages

### During Vault Creation
```
"This pattern is already used by another vault. Please choose a different pattern."
```

### During Pattern Change
```
"This pattern is already used by another vault. Please choose a different pattern."
```

Both messages:
- Are clear and non-technical
- Explain the problem (pattern already used)
- Suggest the solution (choose different pattern)
- Don't reveal sensitive information about the existing vault

## Testing Scenarios

### Test 1: Create Vault with Existing Pattern
1. Create Vault A with pattern X
2. Lock the app
3. Try to create new vault with same pattern X
4. **Expected:** Error shown, return to pattern creation

### Test 2: Change to Existing Pattern
1. Create Vault A with pattern X
2. Create Vault B with pattern Y
3. Open Vault A
4. Try to change pattern to Y
5. **Expected:** Error after confirmation, return to new pattern creation

### Test 3: Change to Unique Pattern
1. Create Vault A with pattern X
2. Change pattern to Z (unique)
3. **Expected:** Success, vault accessible with pattern Z

### Test 4: Multiple Vaults
1. Create Vaults A, B, C with patterns X, Y, Z
2. Try to create vault with X, Y, or Z
3. **Expected:** Error for all three
4. Create vault with pattern W
5. **Expected:** Success

## Performance

- **Collision check:** O(1) file system lookup
- **Overhead:** Negligible (<1ms)
- **No impact** on pattern validation or key derivation speed

## Future Enhancements

Potential improvements:

1. **Vault Switcher**: Show list of available vaults by pattern thumbnail
2. **Vault Naming**: Allow users to name vaults for easier identification
3. **Pattern Hints**: Visual indicator of similar patterns during creation
4. **Collision Statistics**: Track how often collisions occur (should be rare)

## Implementation Checklist

- [x] Add `vaultExists()` method to VaultStorage
- [x] Add `vaultAlreadyExists` error to VaultStorageError
- [x] Add custom error support to PatternValidationError
- [x] Check for collisions in PatternSetupView
- [x] Check for collisions in changeVaultKey()
- [x] Handle collision error in ChangePatternView
- [x] User-friendly error messages
- [x] Return user to pattern creation on collision
- [x] Clear state when collision detected

---

**Status:** ✅ Implemented
**Version:** 1.0
**Date:** January 27, 2026
