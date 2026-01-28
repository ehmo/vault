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

## Sharing a Vault

```
Vault View
        │
        ▼ (tap ⚙️)
┌─────────────────────────────┐
│  Vault Settings             │
│                             │
│  This Vault                 │
│  ├─ Files: 12               │
│  └─ Storage: 45 MB          │
│                             │
│  Pattern                    │
│  └─ Change pattern          │
│                             │
│  Sharing                    │
│  └─ [Share This Vault]  ◄───┼─── NEW
│                             │
│  ...                        │
└─────────────────────────────┘
        │
        ▼ (tap Share This Vault)
┌─────────────────────────────┐
│  Share Vault                │
│                             │
│  Generating phrase...       │
│         ⟳                   │
└─────────────────────────────┘
        │
        ▼
┌─────────────────────────────┐
│  Share Vault                │
│                             │
│  Share phrase:              │
│                             │
│  "The purple elephant       │
│   dances quietly under      │
│   broken umbrellas"         │
│                             │
│  [Copy to Clipboard]        │
│                             │
│  ⚠️ Important               │
│  Anyone with this phrase    │
│  has full access.           │
│                             │
│  [Upload & Share]           │
└─────────────────────────────┘
        │
        ▼ (tap Upload & Share)
┌─────────────────────────────┐
│  Uploading...               │
│         ⟳                   │
│                             │
│  Encrypting files...        │
│  Uploading to iCloud...     │
└─────────────────────────────┘
        │
        ▼
┌─────────────────────────────┐
│  ✓ Vault Shared!            │
│                             │
│  Share this phrase:         │
│  "The purple elephant..."   │
│                             │
│  [Copy]        [Done]       │
└─────────────────────────────┘
```

## Joining a Shared Vault

```
Pattern Lock Screen
        │
        ▼ (tap "Join shared vault")
┌─────────────────────────────┐
│  Join Shared Vault          │
│                             │
│  Enter share phrase:        │
│  ┌───────────────────────┐  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  [Join Vault]               │
└─────────────────────────────┘
        │
        ▼ (enter phrase, tap Join)
┌─────────────────────────────┐
│  Joining...                 │
│         ⟳                   │
│                             │
│  Downloading vault...       │
│  Decrypting files...        │
└─────────────────────────────┘
        │
        ├─ Success ──────────────────────────────────┐
        │                                            │
        └─ Error ───────────────────┐                │
                                    ▼                ▼
                    ┌─────────────────────┐  ┌─────────────────────┐
                    │  Could Not Join     │  │  ✓ Vault Joined!    │
                    │                     │  │                     │
                    │  No vault found     │  │  Files: 12          │
                    │  with this phrase   │  │  Size: 45 MB        │
                    │                     │  │                     │
                    │  [Try Again]        │  │  [Open Vault]       │
                    └─────────────────────┘  └─────────────────────┘
                                                      │
                                                      ▼
                                                  Vault View
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
