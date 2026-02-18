# Session Context

## User Prompts

### Prompt 1

The photo view still starts with images centered at the top (see image). When I take any action, swipe or tap it recenters. But the starting point is still wrong

### Prompt 2

[Image: source: /Users/nan/Downloads/IMG_2139.PNG]

### Prompt 3

Some pictures like this one REDACTED.HEIC are shown incorrectly like this (see image 2). Fix it

### Prompt 4

[Image: source: /Users/nan/Downloads/IMG_2143.PNG]

### Prompt 5

Push these to git

### Prompt 6

build it, test it, and if all is working, send it to testflight

### Prompt 7

[Request interrupted by user]

### Prompt 8

Add a setting to the app settings to restart the onboarding without wiping out the whole vault. I just want to be able to go through the onboarding screen without deleting any data

### Prompt 9

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

### Prompt 10

push it to testflight

### Prompt 11

Base directory for this skill: /Users/nan/.claude/skills/asc-release-flow

# Release flow (TestFlight and App Store)

Use this skill when you need to get a new build into TestFlight or submit to the App Store.

## Preconditions
- Ensure credentials are set (`asc auth login` or `ASC_*` env vars).
- Use a new build number for each upload.
- Prefer `ASC_APP_ID` or pass `--app` explicitly.
- Build must have encryption compliance resolved (see asc-submission-health skill).

## iOS Release

### Prefer...

