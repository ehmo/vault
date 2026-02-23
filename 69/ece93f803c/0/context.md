# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Plan: Retain Original File Dates + "File Date" Sort

## Context
Imported files lose their original creation dates — `createdAt` is always set to `Date()` (import time). User wants to preserve original dates and add a "File Date" sort option, while keeping the default sort by "date added to vault."

## Data Model (4 files)

### `VaultIndexTypes.swift` — `VaultFileEntry`
- Add `originalDate: Date?` field (Codable, nil for old entries = backward compatible)
- Up...

### Prompt 2

Fix the failing tests

