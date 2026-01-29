# User Flows

## App States

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Onboarding │ →  │ Pattern Lock│ →  │   Vault     │
│   (first    │    │  (locked)   │    │ (unlocked)  │
│    launch)  │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  ↑                  │
       │                  └──────────────────┘
       │                     (auto-lock)
       ▼
┌─────────────┐
│   Pattern   │
│    Setup    │
└─────────────┘
```

## First Launch (Onboarding)

```
┌─────────────────────────────────────────────┐
│                 Welcome                      │
│                                             │
│          [Vault icon]                       │
│                                             │
│     Your files, completely private          │
│                                             │
│     • No accounts                           │
│     • No cloud (unless you share)           │
│     • Multiple hidden vaults                │
│                                             │
│           [Get Started]                     │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│              Create Pattern                  │
│                                             │
│     Draw a pattern to create your           │
│     first vault (minimum 6 points)          │
│                                             │
│          ┌─────────────┐                    │
│          │  4x4 Grid   │                    │
│          └─────────────┘                    │
│                                             │
│     This pattern is your key.               │
│     There is no "forgot password".          │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│            Confirm Pattern                   │
│                                             │
│     Draw the same pattern again             │
│                                             │
│          ┌─────────────┐                    │
│          │  4x4 Grid   │                    │
│          └─────────────┘                    │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│           Recovery Phrase                    │
│                                             │
│  Save this phrase - it can recover          │
│  your vault if you forget the pattern:      │
│                                             │
│  "The purple elephant dances quietly        │
│   under the broken umbrella"                │
│                                             │
│         [Copy]  [I've Saved It]             │
└─────────────────────────────────────────────┘
                    │
                    ▼
              Vault View (empty)
```

## Unlocking

### Happy Path

```
Pattern Lock Screen
        │
        ▼ (draw pattern)
┌─────────────────────┐
│ Derive key (1-2s)   │  ← Random delay (timing attack prevention)
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│ Check if duress     │
│ (if yes, destroy    │
│  other vaults)      │
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│ Decrypt index       │
└─────────────────────┘
        │
        ▼
    Vault View (with files)
```

### Wrong Pattern

```
Pattern Lock Screen
        │
        ▼ (draw wrong pattern)
┌─────────────────────┐
│ Derive key (1-2s)   │  ← Same delay (no timing leak)
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│ Decrypt index fails │
│ (silently)          │
└─────────────────────┘
        │
        ▼
    Vault View (empty)   ← No error shown!
```

**Why no error?** Plausible deniability. Attacker cannot know if pattern was wrong or vault is empty.

### Recovery Phrase

```
Pattern Lock Screen
        │
        ▼ (tap "Use recovery phrase")
┌─────────────────────┐
│ Recovery Sheet      │
│                     │
│ Enter your phrase:  │
│ ┌─────────────────┐ │
│ │                 │ │
│ └─────────────────┘ │
│                     │
│ [Recover Vault]     │
└─────────────────────┘
        │
        ▼ (enter phrase, tap button)
┌─────────────────────┐
│ Derive key          │
│ (800k iterations)   │
└─────────────────────┘
        │
        ▼
    Vault View
```

## Adding Files

```
Vault View (files or empty)
        │
        ▼ (tap + or "Add Files")
┌─────────────────────────────┐
│     Add to Vault            │
│                             │
│  [ Take Photo ]             │
│  [ Choose from Photos ]     │
│  [ Import File ]            │
│  [ Cancel ]                 │
└─────────────────────────────┘
        │
        ├─ Take Photo ──────────► Secure Camera ──► Encrypted to vault
        │
        ├─ Choose from Photos ──► Photo Picker ──► Encrypted to vault
        │
        └─ Import File ─────────► File Picker ───► Encrypted to vault
```

## Viewing Files

```
Vault View
        │
        ▼ (tap file)
┌─────────────────────────────┐
│  Secure Image Viewer        │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │    (decrypted image)  │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  [Share]    [Delete]        │
└─────────────────────────────┘
```

**Note:** File is decrypted only when viewed, never written to temp storage.

## Sharing a Vault (Owner)

### First Share / New Share

```
Vault Settings → "Share This Vault"
        │
        ▼
┌─────────────────────────────────────┐
│ Share Settings                      │
│                                     │
│ [Toggle] Set expiration date        │
│          [Date picker if on]        │
│ [Toggle] Limit number of opens      │
│          [Stepper if on: 10]        │
│                                     │
│ [Generate Share Phrase]             │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ Share phrase (one-time use):        │
│                                     │
│ "The purple elephant dances         │
│  quietly under broken umbrellas"    │
│                                     │
│ [Copy to Clipboard]                 │
│                                     │
│ ⚠ This phrase works once.          │
│ After your recipient uses it,       │
│ it will no longer work.             │
│                                     │
│ Uploading: 3 of 12 chunks... ██░░░  │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ ✓ Vault Shared!                     │
│                                     │
│ Share this phrase with your         │
│ recipient:                          │
│ "The purple elephant..."            │
│                                     │
│ [Copy]        [Done]                │
└─────────────────────────────────────┘
```

### Manage Shares

```
Vault Settings → Sharing
├── Shared with 2 people
├── Share #1: Created Jan 28 · Active
│   ├── Expires: Never
│   ├── Last synced: 1h ago
│   └── [Revoke Access]
├── Share #2: Created Jan 29 · Active
│   ├── Expires: Feb 28
│   └── [Revoke Access]
├── [Share with someone new]
└── [Stop All Sharing]
```

### Background Sync

After owner adds/removes files:
1. `ShareSyncManager` debounces changes (30s)
2. Builds `SharedVaultData` from current files
3. Uploads to ALL active share vault IDs
4. Each share encrypted with `SHA256(vaultKey + shareId)`

## Joining a Shared Vault (Recipient)

```
Pattern Lock Screen → "Join shared vault"
        │
        ▼
┌─────────────────────────────┐
│  Enter share phrase:        │
│  ┌───────────────────────┐  │
│  │                       │  │
│  └───────────────────────┘  │
│  [Join Vault]               │
└─────────────────────────────┘
        │
        ▼ (download with progress)
┌─────────────────────────────┐
│  Downloading vault...       │
│  Chunk 3 of 12  ████░░░░    │
└─────────────────────────────┘
        │
        ▼ (phrase is burned: claimed=true)
┌─────────────────────────────┐
│  Set a pattern to unlock    │
│  this vault                 │
│                             │
│  ┌─────────────┐            │
│  │  4x4 Grid   │            │
│  └─────────────┘            │
│  (draw, then confirm)       │
└─────────────────────────────┘
        │
        ▼
┌─────────────────────────────┐
│  ✓ Vault Joined!            │
│  Files imported to vault.   │
│  [Open Vault]               │
└─────────────────────────────┘
        │
        ▼
    Vault View (restricted mode)
```

### Recipient: Daily Use

```
Lock Screen → draw pattern → shared vault opens
┌─────────────────────────────────────┐
│ [Shared Vault · Updated 2h ago]     │
│ [Expires: Feb 28, 2026]             │
│                                     │
│  📷 photo1   📷 photo2             │
│  📄 doc.pdf  📷 photo3             │
│                                     │
│ Banner: "3 new files available"     │
│         [Update Now]                │
└─────────────────────────────────────┘
```

- No camera, import, or delete buttons
- No share sheet on files
- Screenshot blocked (screen goes black on capture)
- Auto-checks for updates on open

### Self-Destruct Scenarios

```
Expired:     "This shared vault has expired." → data deleted
View limit:  "Maximum number of opens reached." → data deleted
Revoked:     "Access has been revoked by owner." → data deleted
```

On destruct: overwrite file data with random bytes, delete index entry, lock vault.

### Error Cases

```
Already claimed: "This share phrase has already been used"
Not found:       "No vault found with this phrase"
Decrypt failed:  "Could not decrypt. Check your phrase."
```

## Duress Flow

```
Pattern Lock Screen
        │
        ▼ (draw duress pattern)
┌─────────────────────────────┐
│ Derive key (1-2s)           │
└─────────────────────────────┘
        │
        ▼
┌─────────────────────────────┐
│ isDuressKey? → YES          │
└─────────────────────────────┘
        │
        ▼
┌─────────────────────────────┐
│ SILENTLY:                   │
│ • Overwrite blob with random│
│ • Delete all index files    │
│ • Preserve duress vault     │
│                             │
│ (takes ~1-2 seconds, hidden │
│  within normal unlock time) │
└─────────────────────────────┘
        │
        ▼
    Duress Vault View
    (looks completely normal)
```

**No indication** that anything happened. Attacker sees a normal-looking vault.

## Settings

```
Vault View → ⚙️ → Vault Settings
┌─────────────────────────────┐
│  Vault Settings             │
│                             │
│  This Vault                 │
│  ├─ Files: 12               │
│  └─ Storage Used: 45 MB     │
│                             │
│  Pattern                    │
│  └─ Change pattern          │
│                             │
│  Recovery                   │
│  ├─ View recovery phrase    │
│  └─ Regenerate phrase       │
│                             │
│  Sharing                    │
│  └─ Share This Vault        │
│                             │
│  Duress                     │
│  └─ [Toggle] Use as duress  │
│                             │
│  App                        │
│  └─ App Settings →          │
│                             │
│  Danger Zone                │
│  └─ [Delete this vault]     │
└─────────────────────────────┘
```

### App Settings

```
Vault Settings → App Settings
┌─────────────────────────────┐
│  App Settings               │
│                             │
│  Pattern Lock               │
│  ├─ [✓] Show visual feedback│
│  ├─ [✓] Randomize grid      │
│  └─ Grid size: 4x4          │
│                             │
│  Security                   │
│  ├─ Auto-wipe: 10 attempts  │
│  └─ Duress pattern →        │
│                             │
│  Backup                     │
│  └─ iCloud Backup →         │
│                             │
│  About                      │
│  ├─ Version: 1.0.0          │
│  └─ Build: Release          │
│                             │
│  Danger Zone                │
│  └─ [Nuclear: Destroy All]  │
└─────────────────────────────┘
```

## Auto-Lock Triggers

The vault automatically locks when:

| Trigger | Behavior |
|---------|----------|
| App backgrounded | Immediate lock |
| Screen recording starts | Immediate lock |
| Lock button tapped | Immediate lock |
| System sleep | Lock on wake |

```
Vault View
        │
        ▼ (app goes to background)
┌─────────────────────────────┐
│ lockVault()                 │
│ • Zero out key in memory    │
│ • Clear currentVaultKey     │
│ • Set isUnlocked = false    │
└─────────────────────────────┘
        │
        ▼
    Pattern Lock Screen
```
