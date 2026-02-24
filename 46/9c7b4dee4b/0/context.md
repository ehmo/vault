# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Performance: Move non-essential launch work off main thread

## Context

Time Profiler trace shows the main thread is blocked for ~31ms after the first frame renders (t=536ms) by Embrace SDK setup, and additional work (VaultStorage init, notification icon warm, TelemetryDeck init) runs synchronously on main during `didFinishLaunchingWithOptions`. While no hangs were detected, this delays touch responsiveness in the early interactive window.

Embrace SDK **require...

### Prompt 2

Push to git

### Prompt 3

Merge

