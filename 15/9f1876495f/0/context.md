# Session Context

## User Prompts

### Prompt 1

You can see from these two images that the screens are not the same.I would like the pattern board to be exactly the same between all of the parts of the app.Make sure that you keep the design equal across the board so that they have the same feel and experience.We can use different color scheme for the shared wall, so it's obvious that it's different

### Prompt 2

[Image: source: /Users/nan/Downloads/IMG_1942.PNG]

[Image: source: /Users/nan/Downloads/IMG_1943.PNG]

### Prompt 3

Push to testflight

### Prompt 4

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

