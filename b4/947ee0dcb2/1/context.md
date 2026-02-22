# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Vertical Drag-to-Select Rows

## Context
Currently drag-to-select only works horizontally (selects individual cells across a row). Vertical drags are rejected (`guard dx > dy`) to allow scrolling. User wants Photos-app-style behavior: dragging vertically selects entire rows (all 3 items per row).

## Changes

**Files**: `PhotosGridView.swift` and `FilesGridView.swift` (identical changes in both)

### 1. Add state
```swift
@State private var isDragVertical = false...

### Prompt 2

Review all code you just written for bugs. Also review other code that can depend on this code and see if there are any issues that could arise from this change. Look for any logical, implementation issues and any edge cases.

### Prompt 3

Review all code you just written for bugs. Also review other code that can depend on this code and see if there are any issues that could arise from this change. Look for any logical, implementation issues and any edge cases.

### Prompt 4

Push all to github. Then send it to both phone and testflight

### Prompt 5

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

