# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Share Extension Test Suite

## Context

The share extension has had multiple memory crash fixes and hardening over the last session. User wants comprehensive tests to catch regressions fast. Currently **zero tests** exist for streaming encryption, staged import manager, or the share extension flow. Existing CryptoEngineTests only covers single-shot encrypt/decrypt, file headers, HMAC, and streaming format detection.

## Plan

Create **3 new test files** covering ...

### Prompt 2

Push it to testflight

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

### Prompt 4

When I switch between light and dark the change is imminent but system is not. It should read what the system's default is and change should be immediate

