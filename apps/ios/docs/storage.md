# Storage Architecture

## Overview

Vault uses a **pre-allocated blob** storage model designed for plausible deniability. All vault data is stored within a single 50MB file filled with random data, making encrypted content indistinguishable from noise.

## Storage Files

```
Documents/
├── vault_data.bin    # 50 MB pre-allocated blob
└── vault_index.bin   # Encrypted file index
```

### vault_data.bin

**Purpose:** Store all encrypted file content

**Properties:**
- Fixed size: 50 MB
- Created on first launch
- Filled with cryptographically random data
- Files written at specific offsets
- Deleted files overwritten with random data

**Structure:**
```
┌─────────────────────────────────────────────────────────────┐
│ 0x00000000  [Random or File 1 encrypted data]               │
│             ...                                             │
│ 0x00100000  [Random or File 2 encrypted data]               │
│             ...                                             │
│ 0x00250000  [Random or deleted file (random)]               │
│             ...                                             │
│ 0x03200000  [Random padding to 50MB]                       │
└─────────────────────────────────────────────────────────────┘
```

### vault_index.bin

**Purpose:** Track file locations and metadata

**Structure (encrypted JSON):**
```swift
struct VaultIndex: Codable {
    var files: [VaultFileEntry]
    var nextOffset: Int
    var totalSize: Int  // 50 MB

    // Owner sharing fields
    var activeShares: [ShareRecord]?   // nil = not shared

    // Recipient sharing fields
    var isSharedVault: Bool?           // true = restricted mode
    var sharedVaultId: String?         // for update checks
    var sharePolicy: SharePolicy?      // restrictions set by owner
    var openCount: Int?                // track opens for maxOpens
}

struct VaultFileEntry: Codable {
    let fileId: UUID
    let offset: Int
    let size: Int
    let encryptedHeaderPreview: Data  // First 64 bytes
    let isDeleted: Bool
}

struct ShareRecord: Codable, Identifiable {
    let id: String                     // share vault ID
    let createdAt: Date
    let policy: SharePolicy
    var lastSyncedAt: Date?
}

struct SharePolicy: Codable, Equatable {
    var expiresAt: Date?               // nil = never
    var maxOpens: Int?                 // nil = unlimited
    var allowScreenshots: Bool         // default false
}
```

**Encryption:** AES-256-GCM with vault key

**Decryption failure:** Returns empty index (not error) → enables plausible deniability

## File Operations

### Store File

```swift
func storeFile(data: Data, filename: String, mimeType: String, with key: Data) throws -> UUID
```

**Process:**
1. Load current index
2. Encrypt file (header + content)
3. Check available space
4. Write to blob at `nextOffset`
5. Add entry to index
6. Save encrypted index

```
Before:
┌──────────────────────────────────────┐
│ [File 1]  [File 2]  [Random...]      │
│ ↑                   ↑                │
│ offset 0            nextOffset       │
└──────────────────────────────────────┘

After adding File 3:
┌──────────────────────────────────────┐
│ [File 1]  [File 2]  [File 3] [Rand.] │
│                     ↑        ↑       │
│                     old      new     │
│                     offset   offset  │
└──────────────────────────────────────┘
```

### Retrieve File

```swift
func retrieveFile(id: UUID, with key: Data) throws -> (header: EncryptedFileHeader, content: Data)
```

**Process:**
1. Load index
2. Find entry by ID (must not be deleted)
3. Seek to offset in blob
4. Read `size` bytes
5. Decrypt and return

### Delete File

```swift
func deleteFile(id: UUID, with key: Data) throws
```

**Process:**
1. Load index
2. Find entry
3. **Overwrite file data with random bytes**
4. Mark entry as `isDeleted = true`
5. Save index

```
Before delete:
┌──────────────────────────────────────┐
│ [File 1]  [File 2]  [File 3] [Rand.] │
└──────────────────────────────────────┘

After delete File 2:
┌──────────────────────────────────────┐
│ [File 1]  [Random]  [File 3] [Rand.] │
│           ↑                          │
│           Overwritten with random    │
└──────────────────────────────────────┘
```

**Note:** Deleted space is NOT reclaimed. This is by design - prevents forensic analysis of deletion patterns.

### List Files

```swift
func listFiles(with key: Data) throws -> [VaultFileEntry]
```

Returns all entries where `isDeleted == false`.

## Encrypted File Format

```
┌────────────────────────────────────────────────────────────┐
│ 4 bytes: Encrypted header size (little-endian uint32)      │
├────────────────────────────────────────────────────────────┤
│ Variable: Encrypted header                                  │
│   ┌────────────────────────────────────────────────────┐   │
│   │ 12 bytes: Nonce                                    │   │
│   │ Variable: Ciphertext                               │   │
│   │ 16 bytes: Auth tag                                 │   │
│   └────────────────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────────┤
│ Variable: Encrypted content                                 │
│   ┌────────────────────────────────────────────────────┐   │
│   │ 12 bytes: Nonce                                    │   │
│   │ Variable: Ciphertext                                    │   │
│   │ 16 bytes: Auth tag                                 │   │
│   └────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

### Header Structure (256 bytes before encryption)

```
Offset  Size   Field
0       16     File ID (UUID)
16      8      Original size (uint64)
24      8      Created timestamp (Double)
32      100    Filename (UTF-8, null-padded)
132     50     MIME type (UTF-8, null-padded)
182     74     Reserved (zeros)
```

## Plausible Deniability

### How It Works

1. **Pre-allocation**: 50MB blob created with random data
2. **Indistinguishability**: Encrypted data looks like random data
3. **No metadata leakage**: File count, sizes not visible
4. **Wrong key = empty**: Decryption failure returns empty vault

### Forensic Analysis Resistance

| Attack | Mitigation |
|--------|------------|
| File carving | No recognizable headers in encrypted data |
| Size analysis | Fixed 50MB blob regardless of content |
| Timestamp analysis | No filesystem timestamps for individual files |
| Deletion detection | Deleted files overwritten with random |
| Usage patterns | All access goes through single blob file |

### Limitations

- Blob file itself is visible
- App must be installed (app presence is detectable)
- Cannot deny having the app
- iCloud backups may leak metadata

## Space Management

### Current Model

- Files written sequentially
- Deleted space not reclaimed
- Eventually blob fills up

### Capacity Calculation

```
Total blob:     50 MB
Index overhead: ~10 KB per file
Per-file overhead: ~300 bytes (header + encryption)

Approximate capacity (single blob, free tier):
- 10 photos (5MB each):   ~50 MB ✓
- 500 documents (100KB):  ~50 MB ✓
- 1 video (50MB):         ~50 MB ✓

Premium users get expansion blobs (50 MB each) for unlimited storage.
```

### Future Enhancement: Compaction

Could implement:
1. Find deleted entries
2. Copy live files to new blob
3. Swap blobs atomically
4. Fill freed space with random

Trade-off: Reveals deletion activity timing.

## File Protection

### iOS Data Protection

```swift
fileManager.createFile(atPath: blobURL.path, contents: nil, attributes: [
    .protectionKey: FileProtectionType.complete
])
```

- `.complete`: File inaccessible when device locked
- Encrypted by iOS at filesystem level
- Additional layer beyond app-level encryption

### Index Protection

```swift
try encrypted.write(to: indexURL, options: [.atomic, .completeFileProtection])
```

- Atomic write prevents corruption
- Complete file protection for iOS encryption

## Vault Destruction

### Normal Delete

Overwrites single file's space with random data.

### Nuclear Wipe

```swift
func destroyAllVaultData() {
    // Overwrite entire blob with random data
    // Delete index files
}
```

Used for:
- Duress trigger
- User-initiated "destroy all"
- Failed attempt threshold

**Process:**
1. Overwrite blob in 1MB chunks with random data
2. Delete index file
3. (Optionally) recreate empty blob

## Performance Considerations

### Read Performance

- Single seek + read operation
- File decryption in memory
- No temp files created

### Write Performance

- Encryption in memory
- Single write at blob offset
- Index update (small file)

### Memory Usage

- Files decrypted into memory
- Large files may use significant RAM
- Consider streaming for video playback

## Backup Integration

### iCloud Backup

- Blob file included in device backup
- Remains encrypted (app-level encryption)
- Can be restored to same device
- Different device = different salt = cannot decrypt

### Export/Import (Future)

For cross-device migration:
1. Export encrypted blob + index
2. Re-encrypt with portable key
3. Import on new device
4. Re-encrypt with new device salt

## Media Optimization

### Overview

Files are automatically optimized during import to reduce storage consumption by up to 85%, while maintaining high visual quality. This applies to all import paths: camera capture, photo picker, file picker, and share extension.

### Setting

`@AppStorage("fileOptimization")` — two options:
- **Optimized** (default): Converts images to HEIC and videos to HEVC 1080p
- **Original**: Stores files at original size and format

### Image Pipeline (HEIC via ImageIO)

1. `CGImageSourceCreateWithURL` reads source image
2. If long edge > 4096px: downsample via `CGImageSourceCreateThumbnailAtIndex`
3. `CGImageDestinationCreateWithURL` writes HEIC at quality 0.6
4. Skip if source is already HEIC/HEIF
5. Peak memory: ~20-50MB (one image bitmap)
6. Typical reduction: 75-85%

### Video Pipeline (HEVC via AVFoundation)

1. `AVURLAsset` from source file
2. `AVAssetExportSession` with `AVAssetExportPresetHEVC1920x1080`
3. Export to temp `.mp4` with network optimization
4. Skip if source is already HEVC at ≤ 1080p
5. Peak memory: ~30-80MB (stream-based, independent of video length)
6. Typical reduction: 85-90%

### Passthrough

Non-media files (PDF, documents, ZIP, etc.) pass through unchanged — no reliable compression without quality loss.

### Filename/MimeType Updates

When optimized, stored filename and mimeType reflect the actual output format:
- `.jpg` / `.png` → `.heic` (`image/heic`)
- `.mov` / `.avi` → `.mp4` (`video/mp4`)

### Implementation

`MediaOptimizer` is a Swift actor (thread-safe, sequential access):

```swift
actor MediaOptimizer {
    static let shared = MediaOptimizer()

    /// Returns (outputURL, outputMimeType, wasOptimized)
    func optimize(fileURL: URL, mimeType: String, mode: Mode) async throws -> (URL, String, Bool)

    /// For UIImage from camera
    func optimizeImage(_ image: UIImage, mode: Mode) async throws -> (URL, String)
}
```

Graceful fallback: if optimization fails for any reason, the original file is used unchanged.

## Code Reference

```
Vault/Core/Storage/
├── VaultStorage.swift      # Main storage API
├── EncryptedBlob.swift     # Low-level blob operations
├── MediaOptimizer.swift    # HEIC/HEVC import optimization
├── ImportIngestor.swift    # Staged import processing
├── FileUtilities.swift     # Thumbnail gen, MIME types
└── SecureDelete.swift      # Secure file wiping
```
