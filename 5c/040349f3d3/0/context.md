# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Auto Background iCloud Backup

## Context
Backups only trigger when the user visits the iCloud Backup settings screen and must stay on that screen until complete. This is because:
1. The auto-backup check lives in `iCloudBackupSettingsView.onAppear`
2. No background execution protection exists — backgrounding kills the backup
3. The vault key is wiped on `willResignActiveNotification`

## Approach
Trigger backup silently after vault unlock. Use `beginBackground...

### Prompt 2

There is a strange bug. On the join shared vault screen, if user taps into the text area, the background screen jumps up (see in the back).

### Prompt 3

[Image: source: /Users/nan/Downloads/IMG_1949.PNG]

