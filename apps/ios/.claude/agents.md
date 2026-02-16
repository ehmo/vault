# Swift Code Quality Rules (SonarQube)

When writing or modifying Swift code in this project, follow these rules to prevent SonarQube issues.

## S1172: Unused Function Parameters

For unused parameters in protocol/delegate methods, use `_` as the internal name. Do NOT use `_paramName`.

```swift
// CORRECT - use bare underscore
func updateUIView(_ _: UIView, context _: Context) {}
func photoOutput(_ _: AVCapturePhotoOutput, didFinishCaptureFor _: AVCaptureResolvedPhotoSettings, error _: Error?) {}
func application(_ _: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {}

// WRONG - creates S1172 + S117 violations
func updateUIView(_ _uiView: UIView, context _: Context) {}
func photoOutput(_ _output: AVCapturePhotoOutput, ...) {}
```

For non-protocol methods, keep the external label and use `_` for internal:
```swift
func packBackupPayload(index: VaultStorage.VaultIndex, key _: Data) throws -> Data {}
```

## S1186: Empty Closures and Functions

Never leave closures or functions empty. Add a comment explaining why.

Use multi-line `//` comments (not inline `/* */`) for SonarQube to recognize them:

```swift
// CORRECT - multi-line comment
Button("Cancel") {
    // No-op: dismiss handled by SwiftUI
}
func updateUIView(_ _: UIView, context _: Context) {
    // No update needed
}
myCallback: { _ in
    // No-op: caller ignores progress
}

// WRONG - SonarQube may not detect inline block comments
Button("Cancel") { /* No-op */ }
myCallback: { _ in /* No-op */ }
```

## S115/S117: Naming Conventions

- Constants must match `^[a-z][a-zA-Z0-9]*$` (camelCase, no underscores)
- Parameters must match `^[a-z][a-zA-Z0-9]*$`
- Never prefix with underscore (except bare `_` for unused params)

```swift
// CORRECT
private let sensitiveKeywords = [...]
private let telemetryLogger = Logger(...)

// WRONG
private let SensitiveKeywords = [...]
private let _setTag = ...
```

## S100: Function Naming

Functions must match `^[a-z][a-zA-Z0-9]*$`. No underscore prefixes.

```swift
// CORRECT
private func performLoadIndex(with key: Data) { ... }

// WRONG
private func _loadIndex(with key: Data) { ... }
```

## S1066: Merge Nested If Statements

Combine nested ifs using comma-separated conditions or `&&`:
```swift
// CORRECT
if !isPremium, let key = derivedKey, !VaultStorage.shared.vaultExists(for: key) { ... }

// WRONG
if !isPremium {
    if let key = derivedKey {
        if !VaultStorage.shared.vaultExists(for: key) { ... }
    }
}
```

## S3358: No Nested Ternary Operations

Extract nested ternaries into computed properties or if/else:
```swift
// CORRECT
private var patternGridOpacity: Double {
    if isVoiceOverActive { return 0.3 }
    else if isProcessing { return 0.5 }
    else { return 1 }
}

// WRONG
.opacity(isVoiceOverActive ? 0.3 : (isProcessing ? 0.5 : 1))
```

## S1301: Use If Instead of Simple Switch

Replace 2-case switch statements with if/else:
```swift
// CORRECT
if fileFilter == .media { ... } else { ... }

// WRONG (only 2 cases)
switch fileFilter {
case .media: ...
default: ...
}
```

## S1659: One Variable Per Declaration

```swift
// CORRECT
var h: CGFloat = 0
var s: CGFloat = 0

// WRONG
var h: CGFloat = 0, s: CGFloat = 0
```

## S3661: Avoid try! in Tests

Use `try` with throwing test functions instead of `try!`:
```swift
// CORRECT
func testFoo() throws {
    let result = try SomeClass()
}

// WRONG
func testFoo() {
    let result = try! SomeClass()
}
```

## S2961: Avoid Backtick-Escaped Reserved Words

Rename properties that use backtick-escaped Swift keywords:
```swift
// CORRECT
static var defaultSettings: VaultMetadata { ... }

// WRONG
static var `default`: VaultMetadata { ... }
```
