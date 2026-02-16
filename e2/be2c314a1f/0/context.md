# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Replace Sentry with Embrace iOS SDK

## Context

Sentry's crash reporting missed the OOM jetsam kill during vault sharing — we had to manually dig through Console.app logs. Embrace is mobile-native and captures full session data including memory pressure and jetsam events. This plan completely removes Sentry and replaces it with Embrace SDK 6.x.

## Scope

**18 files reference Sentry.** The migration is mechanical: replace `SentryManager` internals with Embrace...

