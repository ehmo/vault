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

## Critical Rules

1. **Never**: Commit secrets, force push, delete issues without permission
2. **Always**: 
   - Run tests before push
   - Commit after every successful build
   - Use `git pull --rebase && git push` (never leave work stranded)
3. **Ask first**: New dependencies, multi-project changes, architectural decisions

## Session Workflow

1. Run quality gates (tests/lint/build)
2. Update beads status (`bd close <id>`)
3. Push: `git pull --rebase && bd sync && git push && git status`
4. Update `.scratch-pad.md` with errors/learnings

## Learnings Source

Detailed session history: `.scratch-pad.md` (2,800+ lines)
Quick reference: See subproject AGENTS.md files

**Model preference**: Use opus for subagents
