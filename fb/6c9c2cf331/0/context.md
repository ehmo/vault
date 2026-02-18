# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Fix Media Viewer Issues

## Context
After the VaultViewModel extraction, multiple media viewer bugs surfaced: filter defaulting, image/video centering, video aspect ratio corruption during conversion, and broken zoom. These are regression bugs in the media viewer stack.

## Issues & Root Causes

### 1. Filter defaults to media with documents present
**File:** `VaultViewModel.swift` lines 186-191
**Cause:** `loadFiles()` only switches `.all` -> `.media` when vault...

### Prompt 2

Base directory for this skill: /Users/nan/.claude/skills/xcodebuildmcp

# XcodeBuildMCP

Prefer XcodeBuildMCP over raw `xcodebuild`, `xcrun`, or `simctl`.

If a capability is missing, assume your tool list may be hiding tools (search/progressive disclosure) or not loading tool schemas yet. Use your tool-search or “load tools” mechanism. If you still can’t find the tools, ask the user to enable them in the MCP client's configuration.

## Tools (exact names + official descriptions)

### Sess...

### Prompt 3

Push to testflight

### Prompt 4

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

