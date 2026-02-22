# Vaultaire Documentation

Vaultaire is a privacy-first monorepo with two production surfaces:
- `apps/ios/`: iOS app (SwiftUI, CryptoKit, CloudKit sharing)
- `apps/web/`: static website (Cloudflare Pages, Tailwind v4)

This index is optimized for quick question-to-doc lookup and copy-paste developer workflows.

## Start Here By Question

| Question | Read This First |
|---|---|
| How is the whole monorepo structured? | [Overall Project Design](./overall-project-design.md) |
| How is the iOS app designed today? | [iOS App Design](./ios-app-design.md) |
| What are the core components and data flow? | [Architecture](./architecture.md) |
| What exactly is the threat model and key derivation model? | [Security Model](./security-model.md) |
| How does one-time phrase sharing work end-to-end? | [`apps/ios/docs/sharing.md`](../apps/ios/docs/sharing.md) |
| Where are product and security trade-offs documented? | [`apps/ios/docs/design-decisions.md`](../apps/ios/docs/design-decisions.md) |
| What are the main user journeys? | [`apps/ios/docs/user-flows.md`](../apps/ios/docs/user-flows.md) |
| How does encrypted blob/index storage work? | [`apps/ios/docs/storage.md`](../apps/ios/docs/storage.md) |
| How do I configure CloudKit records and containers? | [`apps/ios/docs/cloudkit-setup.md`](../apps/ios/docs/cloudkit-setup.md) |
| How do I configure subscriptions and IAP products in App Store Connect? | [App Store Connect IAP Setup](./app-store-connect-iap-setup.md) |
| What are current iOS testing priorities and coverage gaps? | [`apps/ios/TEST_PLAN.md`](../apps/ios/TEST_PLAN.md) |
| What are web deployment rules and brand constraints? | [`apps/web/AGENTS.md`](../apps/web/AGENTS.md) |

## Quick Commands

### How do I claim and close work items?

```bash
bd onboard
bd ready
bd show <id>
bd update <id> --status in_progress
```

```bash
bd close <id>
git pull --rebase
bd sync
git push
```

### How do I build and preview the website?

```bash
cd apps/web
npm install
npm run build
npx serve .
```

### How do I build and test the iOS app on simulator?

```bash
cd apps/ios
xcrun simctl list devices available
xcodebuild -project Vault.xcodeproj -scheme Vault -destination 'platform=iOS Simulator,id=<UUID>' -configuration Debug build
xcodebuild -project Vault.xcodeproj -scheme Vault -destination 'platform=iOS Simulator,id=<UUID>' -configuration Debug test
```

## Documentation Map

### Core Project Docs (`docs/`)

| Document | Purpose |
|---|---|
| [Overall Project Design](./overall-project-design.md) | Monorepo boundaries, architecture principles, and release surface map |
| [iOS App Design](./ios-app-design.md) | Current iOS architecture, state model, background jobs, and UX invariants |
| [Architecture](./architecture.md) | Component-level structure and key data/control flows |
| [Security Model](./security-model.md) | Threat model, PBKDF2 strategy, key lifecycle, and deniability properties |
| [App Store Connect IAP Setup](./app-store-connect-iap-setup.md) | Manual ASC setup for subscriptions and lifetime purchase |

### iOS Deep Dives (`apps/ios/docs/`)

| Document | Purpose |
|---|---|
| [`sharing.md`](../apps/ios/docs/sharing.md) | One-time phrase sharing model, recipient controls, and lifecycle |
| [`design-decisions.md`](../apps/ios/docs/design-decisions.md) | Product and engineering trade-offs with rationale |
| [`user-flows.md`](../apps/ios/docs/user-flows.md) | State transitions and main user journeys |
| [`storage.md`](../apps/ios/docs/storage.md) | Encrypted blob/index storage format and constraints |
| [`cloudkit-setup.md`](../apps/ios/docs/cloudkit-setup.md) | CloudKit capability and schema setup guide |
| [`marketing-copy.md`](../apps/ios/docs/marketing-copy.md) | Product messaging copy source for web and launch assets |

### Operating Guides

| Guide | Purpose |
|---|---|
| [`AGENTS.md`](../AGENTS.md) | Monorepo workflow, issue tracking, and quality gates |
| [`apps/ios/AGENTS.md`](../apps/ios/AGENTS.md) | iOS guardrails, build/test commands, and historical pitfalls |
| [`apps/web/AGENTS.md`](../apps/web/AGENTS.md) | Web build/deploy, SEO, static routing, and shared style system |
| [`apps/ios/TEST_PLAN.md`](../apps/ios/TEST_PLAN.md) | Prioritized test coverage plan and regression checklist |

## Notes for AI Assistants

- Treat `docs/overall-project-design.md` as the cross-project source of truth.
- Prefer `apps/ios/docs/*.md` for feature-level iOS details over older summaries.
- Use `apps/ios/AGENTS.md` and `apps/web/AGENTS.md` for the most current build/deploy workflow.
