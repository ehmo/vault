# CloudKit Setup Guide

This guide covers the CloudKit configuration required for vault sharing functionality.

## Prerequisites

- Apple Developer account
- Xcode 15+
- Physical iOS device or simulator with iCloud account

## 1. Enable CloudKit Capability

### In Xcode:

1. Select your project in the navigator
2. Select the "Vault" target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "iCloud"
6. Check "CloudKit"
7. Click "+" next to Containers
8. Create: `iCloud.com.vault.shared`

```
Signing & Capabilities
├── iCloud
│   ├── [✓] CloudKit
│   └── Containers
│       └── iCloud.com.vault.shared (selected)
```

## 2. CloudKit Dashboard Configuration

### Access Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/)
2. Sign in with your Apple Developer account
3. Select your container: `iCloud.com.vault.shared`

### Create Record Type

1. Go to "Schema" → "Record Types"
2. Click "+" to add new record type
3. Name: `SharedVault`
4. Add fields:

| Field Name | Type | Attributes |
|------------|------|------------|
| `encryptedData` | Asset | - |
| `updatedAt` | Date/Time | Queryable, Sortable |
| `version` | Int64 | - |

### Configure Indexes

1. Go to "Schema" → "Indexes"
2. For `SharedVault` record type, ensure:
   - `recordName` is queryable (automatic)
   - `updatedAt` is queryable and sortable

### Deploy to Production

1. Go to "Schema" → "Deploy to Production"
2. Review changes
3. Click "Deploy"

**Important:** Schema changes must be deployed before the app can use them in production.

## 3. Code Configuration

### Container Identifier

In `CloudKitSharingManager.swift`:

```swift
private init() {
    container = CKContainer(identifier: "iCloud.com.vault.shared")
    publicDatabase = container.publicCloudDatabase
}
```

**Note:** Update the identifier if you used a different container name.

### Entitlements

Verify `Vault.entitlements` contains:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.vault.shared</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
</dict>
</plist>
```

## 4. Testing

### Development Environment

1. CloudKit Dashboard has "Development" and "Production" environments
2. Debug builds use Development
3. TestFlight/App Store builds use Production
4. Schema must be deployed to Production for release

### Test iCloud Status

```swift
func checkiCloudStatus() async -> CKAccountStatus {
    do {
        return try await container.accountStatus()
    } catch {
        return .couldNotDetermine
    }
}
```

Possible statuses:
- `.available` - Ready to use
- `.noAccount` - User not signed into iCloud
- `.restricted` - Parental controls or MDM restriction
- `.couldNotDetermine` - Network or other error
- `.temporarilyUnavailable` - iCloud temporarily unavailable

### Test Upload

```swift
// Create test record
let record = CKRecord(recordType: "SharedVault", recordID: CKRecord.ID(recordName: "test"))
record["updatedAt"] = Date()
record["version"] = 1

// Test data as asset
let testData = "Hello CloudKit".data(using: .utf8)!
let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.bin")
try testData.write(to: tempURL)
record["encryptedData"] = CKAsset(fileURL: tempURL)

// Upload
try await container.publicCloudDatabase.save(record)
print("Upload successful!")
```

### Test Download

```swift
let recordID = CKRecord.ID(recordName: "test")
let record = try await container.publicCloudDatabase.record(for: recordID)
print("Download successful: \(record)")
```

### Verify in Dashboard

1. Go to CloudKit Dashboard
2. Select "Data" → "Records"
3. Select "SharedVault" record type
4. You should see your test record

## 5. Error Handling

### Common Errors

| Error Code | Meaning | Solution |
|------------|---------|----------|
| `CKError.notAuthenticated` | No iCloud account | Prompt user to sign in |
| `CKError.networkUnavailable` | No network | Retry later |
| `CKError.networkFailure` | Network error | Retry with backoff |
| `CKError.quotaExceeded` | Storage full | Alert user |
| `CKError.unknownItem` | Record not found | Return "vault not found" |
| `CKError.serverRejectedRequest` | Schema mismatch | Deploy schema |

### Retry Logic

```swift
func uploadWithRetry(_ record: CKRecord, attempts: Int = 3) async throws {
    var lastError: Error?
    for attempt in 1...attempts {
        do {
            try await publicDatabase.save(record)
            return
        } catch let error as CKError where error.code == .networkFailure {
            lastError = error
            let delay = Double(attempt) * 2  // Exponential backoff
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
    throw lastError!
}
```

## 6. Privacy Considerations

### Public Database

Shared vaults use CloudKit's **public database**:
- Records accessible to all app users
- No user authentication for access
- Security relies on encryption, not access control

### What's Stored

| Field | Content | Privacy |
|-------|---------|---------|
| `recordName` | SHA256(phrase) | Cannot reverse to phrase |
| `encryptedData` | AES-encrypted vault | Unreadable without phrase |
| `updatedAt` | Timestamp | Reveals when shared |
| `version` | Integer | No sensitive info |

### What's NOT Stored

- User identity
- Device information
- IP addresses (handled by CloudKit)
- Original filenames (encrypted)

### Data Retention

- Records persist until deleted
- No automatic expiration
- User can delete via `deleteSharedVault(phrase:)`

## 7. Quotas and Limits

### CloudKit Public Database Limits

| Resource | Limit |
|----------|-------|
| Request size | 10 MB |
| Asset size | 250 MB |
| Records per query | 200 |
| Operations per second | Varies |

### Vault Size Considerations

- Each shared vault uploads all files
- Large vaults may hit asset size limit
- Consider chunking for large vaults (future enhancement)

## 8. Production Checklist

- [ ] Container created in Apple Developer portal
- [ ] CloudKit capability enabled in Xcode
- [ ] Container identifier matches code
- [ ] Record type created in CloudKit Dashboard
- [ ] All fields added with correct types
- [ ] Indexes configured for queries
- [ ] Schema deployed to Production
- [ ] Tested on physical device
- [ ] Tested with different iCloud accounts
- [ ] Error handling implemented
- [ ] Network retry logic added

## Troubleshooting

### "Container not found"

1. Check container identifier matches exactly
2. Ensure container is created in Developer portal
3. Check entitlements file

### "Record type not found"

1. Create record type in CloudKit Dashboard
2. Deploy schema to Production
3. Wait a few minutes for propagation

### "Operation not permitted"

1. Check iCloud account is signed in
2. Check app has iCloud permission in Settings
3. Check device has network connectivity

### "Asset upload failed"

1. Check file size (< 250 MB)
2. Check temp file exists before creating CKAsset
3. Verify file has read permissions
