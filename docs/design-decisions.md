# Design Decisions

This document captures key product decisions, trade-offs, and the reasoning behind them.

## Core Philosophy

### "No Accounts, No Cloud (Unless You Choose)"

**Decision:** Local-first architecture with optional sharing.

**Reasoning:**
- Most secure option for sensitive data
- No server to be hacked or subpoenaed
- Works offline
- User controls their data completely

**Trade-off:** No automatic sync between devices. Users must explicitly share.

### "Empty Vault, Not Error"

**Decision:** Wrong patterns show an empty vault instead of "wrong password" error.

**Reasoning:**
- Plausible deniability: Attacker cannot know if pattern is wrong or vault is empty
- Brute-force provides no feedback
- Under coercion, user can claim vault is empty

**Trade-off:** User might think vault is empty when they mistyped pattern. Mitigated by recovery phrase.

### Multiple Vaults Per App

**Decision:** Each pattern unlocks a different vault.

**Reasoning:**
- Separation of concerns (work/personal/secret)
- Duress protection (one vault can destroy others)
- Different security levels per vault

**Trade-off:** More complex mental model. Users must remember which pattern goes where.

## Security Decisions

### PBKDF2 vs Argon2

**Decision:** Use PBKDF2-HMAC-SHA512 with high iteration count.

**Reasoning:**
- Native to iOS (CommonCrypto)
- No external dependencies
- Well-audited, proven secure
- 600k-800k iterations provides sufficient protection

**Trade-off:** Argon2 would be more resistant to GPU attacks, but requires external library.

### Device-Bound Salt

**Decision:** Local vault keys use salt from Secure Enclave.

**Reasoning:**
- Same pattern produces different keys on different devices
- Prevents offline brute-force if storage is copied
- Leverages hardware security

**Trade-off:** Cannot migrate vault to new device via pattern alone. Requires recovery phrase or export feature.

### Fixed Salt for Sharing

**Decision:** Share keys use a fixed, known salt.

**Reasoning:**
- Must produce identical key on any device
- Security relies on phrase entropy (~80+ bits)
- No other way to enable sharing

**Trade-off:** Less secure than device-bound salt. Mitigated by high-entropy phrases.

### 1-2 Second Random Delay

**Decision:** All unlock attempts take 1-2 seconds (random within range).

**Reasoning:**
- Timing attacks cannot detect correct pattern
- Delay hides both key derivation time and duress trigger
- Feels natural (not too fast, not too slow)

**Trade-off:** Slightly slower user experience for legitimate unlocks.

## Storage Decisions

### Pre-Allocated 500MB Blob

**Decision:** Create fixed-size blob filled with random data.

**Reasoning:**
- Encrypted data indistinguishable from random noise
- File size doesn't reveal content amount
- Deletion doesn't change blob size

**Trade-off:**
- Uses 500MB regardless of actual content
- Deleted space not reclaimed
- Limited total capacity

### No Space Reclamation

**Decision:** Deleted files' space is not reused.

**Reasoning:**
- Prevents forensic analysis of deletion patterns
- Simpler implementation
- More secure (no reuse = no data leakage)

**Trade-off:** Eventually vault fills up. User must create new vault.

### Single Index File

**Decision:** One encrypted index file per vault.

**Reasoning:**
- Simple to implement
- Atomic updates
- Fast to load

**Trade-off:**
- Corruption destroys entire vault
- No partial recovery possible

## Sharing Decisions

### One-Time Phrases with Per-Recipient Control

**Decision:** Each share generates a unique, one-time phrase. The phrase serves as both vault ID (SHA256) and encryption key (PBKDF2). After the recipient claims it, the phrase is burned.

**Reasoning:**
- Owner controls exactly who has access
- Forwarding the phrase after claim is useless
- Individual revocation possible via CloudKit `revoked` flag
- Enables per-recipient policies (expiration, view limits, screenshot prevention)

**Trade-off:**
- More complex than a simple shared phrase
- Requires CloudKit for state tracking (claimed, revoked)

### CloudKit Public Database

**Decision:** Use CloudKit public database for shared vaults.

**Reasoning:**
- No server infrastructure needed
- Apple handles scale and availability
- Free for reasonable usage
- No authentication required for access

**Trade-off:**
- Dependent on Apple infrastructure
- Subject to CloudKit quotas
- Public database means anyone can fetch records (security is encryption-based)

### Background Sync with Debounce

**Decision:** Owner file changes auto-sync to all active share recipients after a 30-second debounce.

**Reasoning:**
- Recipient always gets latest files
- Debounce prevents excessive uploads during batch changes
- No conflict resolution needed (owner is sole writer)
- Recipient can manually check for updates on vault open

**Trade-off:** 30-second delay before sync starts. Large vaults take time to re-upload all chunks.

### Memorable Phrase Generation

**Decision:** Use sentence templates with word lists for share phrases.

**Reasoning:**
- Easier to remember than random words
- Higher entropy than user-chosen phrases
- Fun and distinctive
- Easy to communicate verbally

**Trade-off:** Longer than cryptographic phrases. ~80 bits vs potential 128+ bits.

### Chunked Uploads

**Decision:** Split shared vault data into ~50 MB chunks for CloudKit upload.

**Reasoning:**
- CloudKit asset limit is 250 MB
- Smaller chunks allow progress tracking
- Failed chunks can be retried individually
- Sequential upload with progress feedback

**Trade-off:** More CloudKit records to manage. Sync must delete old chunks and upload new ones.

### Client-Side Restrictions (DRM-lite)

**Decision:** Enforce screenshot prevention, expiration, and view limits client-side.

**Reasoning:**
- No server infrastructure to enforce server-side
- Prevents casual copying and sharing
- UITextField.isSecureTextEntry trick blocks iOS screen capture natively
- Good enough for trusted recipients

**Trade-off:** A determined attacker with a jailbroken device can bypass. Encryption is the real security layer; restrictions are convenience controls.

## UX Decisions

### Pattern Lock (Not PIN/Password)

**Decision:** Use pattern-based authentication.

**Reasoning:**
- Faster to enter than password
- More memorable than long PIN
- Harder to shoulder-surf
- Unique to mobile

**Trade-off:**
- Vulnerable to smudge attacks (mitigated by randomization option)
- Lower entropy than strong password
- Requires touch screen

### Grid Randomization Option

**Decision:** Optional randomization of grid node positions.

**Reasoning:**
- Defeats smudge attacks
- User can choose security/convenience balance
- Default off (familiar experience)

**Trade-off:** Harder to develop muscle memory. Must look at screen.

### No Visible File Count

**Decision:** Home screen doesn't show vault count or contents hint.

**Reasoning:**
- Plausible deniability
- No information leakage
- Same appearance regardless of vaults

**Trade-off:** User must unlock to see if vault has content.

### Settings in Two Places

**Decision:** Vault-specific settings (VaultSettingsView) and app-wide settings (AppSettingsView).

**Reasoning:**
- Clear separation of scope
- Per-vault: pattern, recovery, sharing, duress
- App-wide: grid size, feedback, wipe policy

**Trade-off:** Slightly more complex navigation.

## Feature Decisions

### Duress Vault

**Decision:** Allow designating a vault as duress trigger.

**Reasoning:**
- Real-world threat model includes coercion
- Provides plausible deniability under force
- No visible indication of destruction

**Trade-off:**
- Accidental trigger destroys data permanently
- Complex to explain to users
- Ethical considerations (could be misused)

### Recovery Phrase

**Decision:** Generate memorable recovery phrase during setup.

**Reasoning:**
- Backup if pattern forgotten
- Can recover on same device
- User-friendly format

**Trade-off:**
- Must be stored securely by user
- If found, provides vault access
- Device-bound (same device only)

### Auto-Lock on Background

**Decision:** Immediately lock when app goes to background.

**Reasoning:**
- Maximum security
- Prevents screenshot in app switcher
- Consistent behavior

**Trade-off:** Annoying if user switches apps briefly. No grace period.

### No Export/Share Individual Files

**Decision:** (Current) Cannot export or share individual files from vault.

**Reasoning:**
- Simpler implementation
- Security focused (no accidental leakage)
- Clear mental model (vault is sealed)

**Trade-off:** Less convenient for legitimate sharing needs. Future enhancement candidate.

## What We Chose NOT to Do

### No Biometric Unlock

**Why not:**
- Can be compelled by law enforcement
- Pattern provides plausible deniability
- Biometrics = one vault only (no multi-vault)

### No Cloud Backup (Automatic)

**Why not:**
- Security risk
- Different devices = different keys
- User should control data location

### No Team/Organization Features

**Why not:**
- Scope creep
- Requires server infrastructure
- Changes security model fundamentally

### No File Preview Thumbnails

**Why not:**
- Would require decryption
- Could leak information
- Grid shows generic icons only

### No "Forgot Pattern" Flow

**Why not:**
- Would defeat security model
- Recovery phrase is the backup
- No way to verify identity
