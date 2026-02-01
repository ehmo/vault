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
8. Create: `iCloud.app.vaultaire.shared`

```
Signing & Capabilities
├── iCloud
│   ├── [✓] CloudKit
│   └── Containers
│       └── iCloud.app.vaultaire.shared (selected)
```

## 2. CloudKit Dashboard Configuration

### Access Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/)
2. Sign in with your Apple Developer account
3. Select your container: `iCloud.app.vaultaire.shared`

### Create Record Types

Two record types are needed: `SharedVault` (manifest) and `SharedVaultChunk` (file data).

#### SharedVault (Manifest)

1. Go to "Schema" → "Record Types"
2. Click "+" to add new record type
3. Name: `SharedVault`
4. Click "Create Record Type"

**Note:** CloudKit auto-creates fields in Development when the app first saves a record. The expected fields are:

| Field Name | Type | Purpose |
|------------|------|---------|
| `shareVaultId` | String | Unique ID for this share |
| `updatedAt` | Date/Time | Last sync timestamp |
| `version` | Int64 | Manifest version for update detection |
| `ownerFingerprint` | String | Key fingerprint of vault owner |
| `chunkCount` | Int64 | Number of chunk records |
| `claimed` | Int64 | 1 after recipient downloads (one-time use) |
| `revoked` | Int64 | 1 when owner revokes access |
| `policy` | Asset | Encrypted SharePolicy (expiration, max opens) |

#### SharedVaultChunk (File Data)

1. Click "+" to add another record type
2. Name: `SharedVaultChunk`
3. Click "Create Record Type"

| Field Name | Type | Purpose |
|------------|------|---------|
| `chunkData` | Asset | Encrypted file data (~50 MB per chunk) |
| `chunkIndex` | Int64 | Order index (0-based) |
| `vaultId` | String | Reference to parent shareVaultId |

### Configure Indexes

After fields exist (either manually created or auto-created by first upload):

**SharedVault:**
1. Click "Edit Indexes" on the SharedVault record type
2. Ensure `recordName` is queryable (automatic)
3. Add queryable + sortable index for `updatedAt`
4. Add queryable index for `shareVaultId`

**SharedVaultChunk:**
1. Click "Edit Indexes" on the SharedVaultChunk record type
2. Ensure `recordName` is queryable (automatic)
3. Add queryable index for `vaultId`
4. Add sortable index for `chunkIndex`

### Deploy to Production

1. Run the app in Development first to auto-create the schema
2. Go to "Schema" → "Deploy to Production"
3. Review changes
4. Click "Deploy"

**Important:** Schema changes must be deployed before the app can use them in production.
Run the app once in Development to ensure all fields are created before deploying.

## 3. Code Configuration

### Container Identifier

In `CloudKitSharingManager.swift`:

```swift
private init() {
    container = CKContainer(identifier: "iCloud.app.vaultaire.shared")
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
        <string>iCloud.app.vaultaire.shared</string>
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

### Test Upload (Manifest + Chunk)

```swift
// Create manifest record
let manifestId = CKRecord.ID(recordName: "test-share-id")
let manifest = CKRecord(recordType: "SharedVault", recordID: manifestId)
manifest["shareVaultId"] = "test-share-id"
manifest["updatedAt"] = Date()
manifest["version"] = 1
manifest["ownerFingerprint"] = "test-fingerprint"
manifest["chunkCount"] = 1
manifest["claimed"] = 0
manifest["revoked"] = 0

try await container.publicCloudDatabase.save(manifest)
print("Manifest upload successful!")

// Create chunk record
let chunkId = CKRecord.ID(recordName: "test-share-id_chunk_0")
let chunk = CKRecord(recordType: "SharedVaultChunk", recordID: chunkId)
let testData = "Hello CloudKit".data(using: .utf8)!
let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("chunk0.bin")
try testData.write(to: tempURL)
chunk["chunkData"] = CKAsset(fileURL: tempURL)
chunk["chunkIndex"] = 0
chunk["vaultId"] = "test-share-id"

try await container.publicCloudDatabase.save(chunk)
print("Chunk upload successful!")
```

### Test Download

```swift
// Fetch manifest
let manifestId = CKRecord.ID(recordName: "test-share-id")
let manifest = try await container.publicCloudDatabase.record(for: manifestId)
let chunkCount = manifest["chunkCount"] as? Int ?? 0
print("Manifest: \(chunkCount) chunks")

// Fetch chunk
let chunkId = CKRecord.ID(recordName: "test-share-id_chunk_0")
let chunk = try await container.publicCloudDatabase.record(for: chunkId)
print("Chunk download successful: \(chunk)")
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
| `shareVaultId` | Random UUID | No link to owner |
| `chunkData` | AES-encrypted file data | Unreadable without phrase |
| `policy` | Encrypted SharePolicy | Unreadable without phrase |
| `updatedAt` | Timestamp | Reveals when shared |
| `claimed` | Boolean flag | Reveals if phrase was used |
| `ownerFingerprint` | Key fingerprint | Identifies owner's vault key |

### What's NOT Stored

- User identity
- Device information
- IP addresses (handled by CloudKit)
- Original filenames (encrypted within chunks)

### Data Retention

- Records persist until owner deletes or revokes
- Owner can revoke individual shares or stop all sharing
- Revoked shares set `revoked = true` on manifest
- Recipient detects revocation on next vault open

## 7. Quotas and Limits

### CloudKit Public Database Limits

| Resource | Limit |
|----------|-------|
| Request size | 10 MB |
| Asset size | 250 MB |
| Records per query | 200 |
| Operations per second | Varies |

### Vault Size Considerations

- Files are split into ~50 MB chunks to stay within CloudKit's 250 MB asset limit
- Each chunk is a separate `SharedVaultChunk` record
- Large vaults generate many chunk records (e.g. 500 MB vault = ~10 chunks)
- Sync updates delete old chunks and upload new ones

## 8. Production Checklist

- [ ] Container created in Apple Developer portal
- [ ] CloudKit capability enabled in Xcode
- [ ] Container identifier matches code
- [ ] `SharedVault` record type created in CloudKit Dashboard
- [ ] `SharedVaultChunk` record type created in CloudKit Dashboard
- [ ] All fields added with correct types on both record types
- [ ] Indexes configured for queries (shareVaultId, vaultId, chunkIndex)
- [ ] Schema deployed to Production
- [ ] Tested manifest + chunk upload/download on physical device
- [ ] Tested one-time claim (claimed flag prevents reuse)
- [ ] Tested revocation (revoked flag)
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

1. Each chunk must be < 250 MB (default ~50 MB)
2. Check temp file exists before creating CKAsset
3. Verify file has read permissions
4. Check that chunkIndex and vaultId are set on SharedVaultChunk records
