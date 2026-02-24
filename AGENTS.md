# Agent Instructions — Vaultaire

**Monorepo**: iOS app + static website. Issue tracking: `bd` (beads) — run `bd onboard` first.

## Quick Start

```bash
bd ready                          # Find work
bd show <id>                      # View issue
bd update <id> --status in_progress  # Claim
bd sync && git push              # Complete
```

## Structure

| Path | Stack | Docs |
|------|-------|------|
| `apps/ios/` | SwiftUI, CloudKit, CryptoKit | `apps/ios/AGENTS.md` |
| `apps/web/` | Cloudflare Pages, Tailwind v4 | `apps/web/AGENTS.md` |

## Deployment (MANDATORY — use scripts, never ad-hoc)

```bash
# Install to physical iPhone (Debug build)
./scripts/deploy-phone.sh          # build + install
./scripts/deploy-phone.sh --launch # build + install + launch

# Upload to TestFlight (Release archive)
./scripts/deploy-testflight.sh          # archive + export + upload (current build number)
./scripts/deploy-testflight.sh --bump   # bump build number first, then archive + upload

# Deploy website to Cloudflare Pages
./scripts/deploy-web.sh                 # build CSS + deploy to production
./scripts/deploy-web.sh --preview       # build CSS + deploy to preview URL
```

**NEVER** run xcodebuild archive/export, asc builds upload, or wrangler pages deploy manually. Always use the scripts.
When asked to "deploy", "push to phone", "upload to TestFlight", "push to devices", or "deploy the website" — use these scripts.

## CRITICAL: UI/UX Immutable Guardrails (MUST READ)

**Before making ANY UI changes, read `.ai/GUARDRAILS.md`. Violations are P0 bugs.**

The three sacred rules:
1. **PATTERN BOARD NEVER MOVES** - Must stay centered, errors appear below with fixed spacing
2. **NO LAYOUT SHIFTS** - Fixed heights, use `Color.clear` placeholders, never let UI jump
3. **TEXT NEVER TRUNCATES** - Always `.lineLimit(nil)` on descriptive text

These rules are non-negotiable. Breaking them requires immediate rollback.

## Critical Rules

1. **Never**: Commit secrets, force push, delete issues without permission
2. **Always**: 
   - Run tests before push
   - Commit after every successful build
   - Use `git pull --rebase && git push` (never leave work stranded)
   - Read `.ai/GUARDRAILS.md` before any UI changes
3. **Ask first**: New dependencies, multi-project changes, architectural decisions

## Session Workflow

1. Run quality gates (tests/lint/build)
2. Update beads status (`bd close <id>`)
3. Push: `git pull --rebase && bd sync && git push && git status`
4. Update `.scratch-pad.md` with errors/learnings

## Learnings Source

Pitfalls, preferences, and corrections: `.scratch-pad.md`
Quick reference: See subproject AGENTS.md files

**Model preference**: Use opus for subagents

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Auto-syncs to JSONL for version control
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update bd-42 --status in_progress --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs with git:

- Exports to `.beads/issues.jsonl` after changes (5s debounce)
- Imports from JSONL when newer (e.g., after `git pull`)
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

<!-- END BEADS INTEGRATION -->

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
