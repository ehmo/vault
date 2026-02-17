# Overall Project Design

## Purpose

Vaultaire is a privacy-first product built around one core promise: user data stays user-controlled, with no account requirement and no server-side access to decrypted content.

This document describes the design of the **entire monorepo**: iOS app, website, design assets, docs, and release workflow.

## Scope

The repository is a monorepo with three primary product-facing surfaces:

1. `apps/ios/` - Main iOS app and Share Extension.
2. `web/` - Static marketing + legal + universal-link support pages.
3. `design/` - Shared visual assets and brand source files.

Supporting directories:

1. `docs/` - Product and technical documentation.
2. `outputs/` - Build artifacts or generated outputs.

## Architectural Principles

1. **Local-first security**: encryption/decryption happens on-device.
2. **No account dependency**: app functionality does not require user identity.
3. **Optional cloud workflows**: cloud is used only when users explicitly choose sharing/backup.
4. **Deterministic UX guardrails**: extensive Maestro flows protect high-risk UI paths.
5. **Incremental background work**: long transfers are resumable and persisted.

## Monorepo Topology

| Area | Responsibility | Runtime/Platform |
|---|---|---|
| `apps/ios/Vault/` | Core app, cryptography, storage, sharing, onboarding, settings | iOS 17+ |
| `apps/ios/Vault/Extensions/ShareExtension/` | Inbound share flow from Photos/Files | iOS Share Extension |
| `apps/ios/maestro/` | End-to-end test automation flows | Maestro |
| `web/` | Landing page, legal pages, AASA, redirects | Cloudflare Pages |
| `docs/` | Architecture/security/product docs | Markdown |
| `design/` | Logos and visual design material | Design assets |

## Subsystem Design

### iOS Product Surface

The iOS app is split into layered modules:

1. **App** (`VaultApp.swift`, `ContentView.swift`): startup, global state, root routing.
2. **Core**:
   1. `Crypto` - key derivation and encryption primitives.
   2. `Storage` - encrypted blobs/indexes, staged import ingest, iCloud backup.
   3. `Sharing` - CloudKit share records/chunks, upload queueing/resume, deep links.
   4. `Security` - Secure Enclave integration, duress logic, recovery phrase generation.
   5. `Billing` - StoreKit 2 subscriptions and entitlement checks.
   6. `Telemetry` - Embrace + analytics wrappers.
3. **Features**:
   1. Onboarding, Pattern Lock, Vault Viewer, Sharing screens, Settings, Camera.
4. **UI**:
   1. Theme tokens and shared components (loaders, cards, banners, controls).

### Web Product Surface

The website is static, intentionally simple:

1. **Pages**:
   1. `index.html` (marketing), `privacy/`, `terms/`, `s/` (share fallback).
2. **Universal links**:
   1. `.well-known/apple-app-site-association` served with strict headers.
3. **Styling**:
   1. Tailwind CSS v4 via `styles/input.css` -> `styles/output.css`.
4. **Deployment**:
   1. Cloudflare Pages using `_headers` and `_redirects`.

### Shared Design Surface

Brand and style consistency is enforced across app and web:

1. Semantic color tokens (background/surface/text/highlight/accent).
2. Shared visual language documented in `apps/ios/DESIGN.md`.
3. Asset-driven theming (`VaultBackground`, `VaultSurface`, etc.) on iOS.

## Data and Control Flows (Cross-Project View)

### Inbound Content Flow

1. User shares media/documents to Share Extension.
2. Extension derives vault key from pattern and encrypts attachments.
3. Encrypted payload is staged into app-group storage.
4. Main app ingests staged files on vault unlock with progress feedback.

### Outbound Sharing Flow

1. User starts share from vault settings.
2. Upload job is persisted and chunked for CloudKit public DB.
3. Recipient claims via one-time phrase and imports to local storage.
4. Ongoing sync uses incremental chunk updates.

### Backup Flow

1. User enables iCloud backup.
2. Local encrypted vault payload is packaged and chunk-uploaded to private DB.
3. Restore reads metadata/chunks and reconstructs vault locally.

## Runtime Boundaries

1. **On-device trust boundary**:
   1. Key material and encrypted files remain local by default.
2. **CloudKit public DB boundary**:
   1. Used for shared vault manifests/chunks.
3. **CloudKit private DB boundary**:
   1. Used for user backups.
4. **Static web boundary**:
   1. No dynamic backend; primarily distribution, legal, and deep-link support.

## Build, Test, and Release Design

### iOS

1. Build/test via Xcode + simulator test target.
2. UI regression coverage via Maestro flows in `apps/ios/maestro/flows`.
3. TestFlight distribution via ASC CLI (`asc publish testflight --wait`).

### Web

1. `npm run build` compiles Tailwind assets.
2. Static deploy to Cloudflare Pages.

## Observability and Diagnostics

1. Structured `os.Logger` usage in core managers.
2. Embrace integration for runtime telemetry and error breadcrumbs.
3. TestFlight and console logs used for production-like issue triage.

## Design Constraints and Non-Goals

1. No server-hosted account model.
2. No direct server-side access to decrypted user content.
3. No reliance on dynamic backend services for core web experience.
4. Platform consistency prioritized over per-screen one-off styling.

## Current Design Risks

1. iOS background execution is best-effort; OS may still terminate work.
2. Cloud availability and account state can delay backup/share operations.
3. UI regressions can emerge from implicit SwiftUI/UIView animation behavior.

## Evolution Strategy

1. Keep monorepo split by runtime boundary (`apps/ios`, `web`, `docs`, `design`).
2. Treat docs and Maestro flows as first-class change artifacts.
3. Preserve stable semantic UI tokens and architecture invariants while iterating features.
