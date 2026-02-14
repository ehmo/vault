# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Reduce Blob Size to 50MB + Multi-Blob iCloud Backup

## Context
500MB pre-allocated blobs cause iCloud backup failures (exceeds CloudKit's 250MB CKAsset limit, slow uploads, unreliable over cellular). Additionally: backup only saves `vault_data.bin` (ignores expansion blobs = silent data loss for premium users), and doesn't backup index files (cross-device restore loses master key = all files unrecoverable).

Fix: reduce blob size to 50MB, redesign backup to hand...

### Prompt 2

>  Manual CloudKit step still required: Add VaultBackupChunk record type to CloudKit Dashboard (Development) with fields chunkData (Asset), chunkIndex (Int64),
  backupId (String), plus add formatVersion/chunkCount/backupId fields to VaultBackup.

Tell me exactly what I need to do

### Prompt 3

Both done. Publish the app to testflight

