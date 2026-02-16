# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Fix OOM Crash During Vault Sharing — Streaming SVDF Build

## Context
Vault sharing crashes (jetsam/OOM kill) on large vaults (96 files, 48.8MB video). Root cause: `startBackgroundUpload` accumulates ALL re-encrypted `SharedFile` objects in a `sharedFiles` array (~total_vault_size), then `SVDFSerializer.buildFull` copies them all into a new `Data` blob (~total_vault_size again). Peak memory = 2x total vault size. For the crashing vault: ~200MB peak.

## Approac...

### Prompt 2

deploy to testflight

### Prompt 3

Base directory for this skill: /Users/nan/.claude/skills/asc-xcode-build

# Xcode Build and Export

Use this skill when you need to build an app from source and prepare it for upload to App Store Connect.

## Preconditions
- Xcode installed and command line tools configured
- Valid signing identity and provisioning profiles (or automatic signing enabled)

## iOS Build Flow

### 1. Clean and Archive
```bash
xcodebuild clean archive \
  -scheme "YourScheme" \
  -configuration Release \
  -archiveP...

