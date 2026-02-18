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

