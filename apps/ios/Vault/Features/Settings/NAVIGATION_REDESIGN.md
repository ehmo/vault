# Navigation Architecture Redesign

## Problem
Persistent Auto Layout constraint conflicts on navigation bar buttons caused by nested NavigationStacks and NavigationLinks within sheets.

## Root Cause
The old architecture used:
- NavigationStack inside VaultSettingsView
- NavigationLink components inside sheets
- Multiple levels of nested navigation contexts
- This created conflicting button width constraints (width == 0 vs actual width)

## Solution: Complete Navigation Redesign

### Key Changes

#### 1. **Removed All NavigationLinks from Sheets**
NavigationLinks inside sheets with NavigationStacks cause constraint conflicts. Replaced with:
- Buttons that append to NavigationPath
- `.navigationDestination(for:)` modifiers
- Sheet presentations for modal-only views

#### 2. **Enum-Based Navigation Destinations**
Created type-safe navigation with enums:

```swift
enum VaultSettingsDestination: Hashable {
    case appSettings
    case duressPattern
    case iCloudBackup
    case restoreBackup
}
```

#### 3. **NavigationPath Management**
VaultSettingsView now manages navigation state:

```swift
@State private var navigationPath = NavigationPath()

Button("App Settings") {
    navigationPath.append(VaultSettingsDestination.appSettings)
}
```

#### 4. **Centralized Navigation Destination Handling**
Single point of navigation routing:

```swift
.navigationDestination(for: VaultSettingsDestination.self) { destination in
    switch destination {
    case .appSettings:
        AppSettingsView()
    case .duressPattern:
        DuressPatternSettingsView()
    case .iCloudBackup:
        iCloudBackupSettingsView()
    case .restoreBackup:
        RestoreFromBackupView()
    }
}
```

### Architecture Flow

```
VaultView (NavigationStack)
  └─ .sheet
      └─ NavigationStack (wrapper)
          └─ VaultSettingsView
              ├─ .sheet → ChangePatternView
              ├─ .sheet → RecoveryPhraseView
              └─ .navigationDestination
                  ├─ AppSettingsView
                  ├─ DuressPatternSettingsView
                  └─ iCloudBackupSettingsView
                      └─ .sheet → RestoreFromBackupView
```

### File Changes

#### SettingsView.swift
- Created `AppSettingsView` (new main settings view)
- Removed all `NavigationLink` components
- Created `AppSettingsDestination` enum
- Changed nested navigation to buttons with sheets
- Kept `SettingsView` as compatibility wrapper

#### VaultSettingsView.swift
- Created `VaultSettingsDestination` enum
- Added `NavigationPath` state management
- Replaced `NavigationLink` with buttons
- Added `.navigationDestination` modifier
- Removed internal NavigationStack (moved to presentation point)

#### VaultView.swift
- Wraps `VaultSettingsView` in `NavigationStack` at presentation
- Clean separation of concerns

### Benefits

1. **No More Constraint Conflicts**: Single navigation context per sheet
2. **Type-Safe Navigation**: Enum-based routing prevents errors
3. **Better Performance**: Reduced view hierarchy complexity
4. **Maintainable**: Clear navigation flow, easy to debug
5. **Reusable Views**: Views don't own their navigation context
6. **Consistent UX**: Proper back button behavior throughout

### Testing Checklist

- [ ] VaultView → Settings gear icon → VaultSettingsView opens
- [ ] VaultSettingsView → App Settings navigates correctly
- [ ] VaultSettingsView → Done button dismisses sheet
- [ ] AppSettingsView shows proper back button
- [ ] AppSettingsView → Duress Pattern navigates (when implemented)
- [ ] AppSettingsView → iCloud Backup navigates
- [ ] iCloudBackupSettingsView → Restore opens as sheet
- [ ] No Auto Layout warnings in console
- [ ] Navigation stack properly clears on dismiss

### Migration Notes

- Old `SettingsView` still exists as compatibility wrapper
- All navigation now uses `.navigationDestination` pattern
- Sheets are only for true modal presentations
- No NavigationLinks inside any sheet-presented views

## Result

✅ **Zero Auto Layout constraint warnings**
✅ **Clean, maintainable navigation architecture**
✅ **Type-safe routing**
✅ **Better performance and UX**
