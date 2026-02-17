# Agent Instructions

Vaultaire monorepo — iOS app, static website, shared design assets.

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Subprojects

| Path | Description | Instructions |
|------|-------------|--------------|
| `apps/ios/` | iOS app (SwiftUI, CloudKit, CryptoKit) | `apps/ios/AGENTS.md` |
| `web/` | Static site (Cloudflare Pages, Tailwind, htmx) | `web/AGENTS.md` |

Each subproject has its own `AGENTS.md` with project-specific instructions that take precedence over this file.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Boundaries

**Never**:
- Commit secrets, credentials, or `.env` files
- Force push to any branch
- Delete issues without explicit permission
- Use "high"/"medium"/"low" for priority (use 0-4 or P0-P4)

**Ask First**:
- Adding new dependencies
- Modifying shared configuration files
- Changes affecting multiple subprojects
- Architectural decisions with multiple valid approaches

**Always**:
- Use opus model for subagents
- Track multi-session work in Beads; use TodoWrite for single-session tasks
- Keep cross-project architecture/design docs in `docs/`; keep iOS feature-deep docs in `apps/ios/docs/`

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

1. **File issues for remaining work** — Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) — Tests, linters, builds
3. **Update issue status** — Close finished work, update in-progress items
4. **PUSH TO REMOTE**:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** — Clear stashes, prune remote branches
6. **Verify** — All changes committed AND pushed
7. **Hand off** — Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing — that leaves work stranded locally
- NEVER say "ready to push when you are" — YOU must push
- If push fails, resolve and retry until it succeeds
- **COMMIT AND PUSH AFTER EVERY SUCCESSFUL BUILD** — small, frequent commits prevent losing work
- **FIX ALL BUILD WARNINGS BEFORE COMMITTING** — at session end, run a full build and fix every warning and error in project code before the final commit. Xcode/system warnings (e.g. AppIntents metadata) can be ignored.

After every task update the relevant AGENTS.md with learnings.

## Scratch Pad (Continual Learning)

A persistent scratch pad at `.scratch-pad.md` tracks errors, corrections, preferences, and learnings across sessions.

**Session Start**: Read `.scratch-pad.md` before doing any work.

**Session End**: Update `.scratch-pad.md` with:
1. **Session Log** entry — query summary, approach, errors, corrections, key learnings
2. **Error Tracker** updates
3. **Corrections and Preferences** updates
4. **Anticipated Improvements** updates
5. **Cumulative Learnings** summary

**Rules**:
- Every session gets a numbered entry
- By session 3+, proactively apply patterns from logged errors/preferences
- Keep entries concise — working reference, not journal
- Commit `.scratch-pad.md` alongside code changes

## Plan Mode

- Make plans extremely concise. Sacrifice grammar for brevity.
- End each plan with unresolved questions (if any).
