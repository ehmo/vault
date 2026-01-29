# Vault Documentation

Vault is a secure file storage app for iOS with pattern-based encryption and plausible deniability.

## Documentation Index

| Document | Description |
|----------|-------------|
| [Architecture](./architecture.md) | System design, components, and data flow |
| [Security Model](./security-model.md) | Encryption, key derivation, and threat model |
| [Sharing](./sharing.md) | One-time phrase sharing with per-recipient controls |
| [Design Decisions](./design-decisions.md) | Key product decisions and trade-offs |
| [User Flows](./user-flows.md) | Key user journeys and interactions |
| [Storage](./storage.md) | File storage and plausible deniability |
| [CloudKit Setup](./cloudkit-setup.md) | iCloud configuration for sharing |

## Quick Overview

### Core Concepts

**Multiple Vaults**: Each pattern unlocks a different vault. Wrong patterns show an empty vault (not an error), making it impossible to know if a vault exists.

**Plausible Deniability**: All data stored in a pre-allocated random blob. Encrypted data is indistinguishable from random noise.

**Duress Protection**: A special pattern can be designated to silently destroy all other vaults while appearing normal.

**Sharing**: Vaults can be shared via one-time phrases with per-recipient controls. Each phrase can only be claimed once. The owner can revoke access, set expiration dates, limit view counts, and prevent screenshots. Changes auto-sync to all recipients.

### Key Technologies

- Swift/SwiftUI (iOS 17+)
- CryptoKit (AES-256-GCM)
- CommonCrypto (PBKDF2)
- Secure Enclave (device-bound keys)
- CloudKit (shared vault sync)
