# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Custom Vault Naming

## Context

Vault names are auto-generated from pattern grid letters (e.g. "Vault DKVS"). Users want to set custom names that:
- Replace the auto-generated name
- Persist across lock/unlock cycles
- Carry through shared vaults (same name regardless of recipient's letter assignments)

Already done (this session): auto-generated names capped at 4 letters, toolbar has `.lineLimit(1)`.

## Data Flow (Current)

1. Pattern drawn -> `GridLetterManag...

### Prompt 2

Finish it

### Prompt 3

There is a weird bug. When user finishes the onboarding and they get to the phrase part and write a custom phrase, the vault creation doesn't work (see video
  /Users/nan/Downloads/ScreenRecording_02-21-2026\ 18-55-07_1.mov). Investigate why. If the pre generated phrase is used it works fine. Also they used camel case
  sentence but that hopefully shouldn't have an impact. Anyway investigate the cause, fix it and create a proper test to catch this.

