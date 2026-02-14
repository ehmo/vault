# Vaultaire Pro Paywall — Figma Structure for RevenueCat Import

> Build this in Figma using **Auto Layout** on every frame. Use the exact
> layer names shown below — the RevenueCat plugin reads them.

## Frame Setup

- **Frame name:** `Vaultaire Pro Paywall`
- **Size:** 393 x 852 (iPhone 15 Pro)
- **Auto Layout:** Vertical, spacing 20, padding 20h / 16t / 32b
- **Fill:** #1C1C1E (vaultBackground)
- **Clip contents:** ON

---

## Color Tokens

| Token             | Hex       | Usage                          |
|-------------------|-----------|--------------------------------|
| Background        | `#1C1C1E` | Full background                |
| Glass Card        | `#2C2C2E` | 80% opacity, corner radius 12 |
| Glass Card Border | `#3A3A3C` | 1px, 40% opacity               |
| Text Primary      | `#FFFFFF` | Titles, labels                 |
| Text Secondary    | `#8E8E93` | Subtitles, captions            |
| Accent            | `#8B5CF6` | Purple brand — badges, checks  |
| Accent Text       | `#FFFFFF` | Text on accent backgrounds     |
| Divider           | `#3A3A3C` | 30% opacity                    |

---

## Layer Tree (top → bottom, all Auto Layout)

```
Vaultaire Pro Paywall                          ← Top-level frame
│
├─ Header                                      ← VStack, center-aligned, spacing 8
│  ├─ "Unlock Vaultaire Pro"                   ← Text: 28pt bold, #FFF
│  └─ "Full privacy, your terms."              ← Text: 15pt regular, #8E8E93
│
├─ BenefitsTable                               ← VStack, spacing 0, fill: glass card
│  │
│  ├─ TableHeader                              ← HStack, spacing 0, pad 16h 10v
│  │  ├─ "Feature"                             ← Text: 11pt semibold, #8E8E93, fill
│  │  ├─ "FREE"                                ← Text: 11pt semibold, #8E8E93, w56
│  │  └─ "PRO"                                 ← Text: 11pt semibold, #8B5CF6, w56
│  │
│  ├─ Divider                                  ← Rectangle 1px, #3A3A3C @ 30%
│  │
│  ├─ Row                                      ← HStack, pad 16h 8v
│  │  ├─ "Photos per vault"                    ← Text: 15pt, #FFF, fill
│  │  ├─ "100"                                 ← Text: 11pt medium, #FFF, w56, center
│  │  └─ "∞"                                   ← Text: 11pt medium, #FFF, w56, center
│  │
│  ├─ Row                                      ← (same structure)
│  │  ├─ "Videos per vault"
│  │  ├─ "10"
│  │  └─ "∞"
│  │
│  ├─ Row
│  │  ├─ "Vaults"
│  │  ├─ "5"
│  │  └─ "∞"
│  │
│  ├─ Row
│  │  ├─ "Duress vault"
│  │  ├─ "—"                                   ← Text: 15pt, #8E8E93
│  │  └─ Icon(check)                           ← Icon: #8B5CF6
│  │
│  ├─ Row
│  │  ├─ "Vault sharing"
│  │  ├─ "—"
│  │  └─ Icon(check)
│  │
│  ├─ Row
│  │  ├─ "iCloud backup"
│  │  ├─ "—"
│  │  └─ Icon(check)
│  │
│  ├─ Row
│  │  ├─ "Pattern encryption"
│  │  ├─ Icon(check)                           ← Both FREE and PRO get check
│  │  └─ Icon(check)
│  │
│  └─ Row
│     ├─ "Plausible deniability"
│     ├─ Icon(check)
│     └─ Icon(check)
│
├─ Plans                                       ← VStack, spacing 10
│  │
│  ├─ Package (Component Set)                  ← MONTHLY — see Package section below
│  │  ├─ State=Default
│  │  └─ State=Selected
│  │
│  ├─ Package (Component Set)                  ← YEARLY
│  │  ├─ State=Default
│  │  └─ State=Selected
│  │
│  └─ Package (Component Set)                  ← LIFETIME
│     ├─ State=Default
│     └─ State=Selected
│
├─ Purchase Button                             ← EXACT name "Purchase Button"
│  └─ "Subscribe"                              ← Text: 17pt bold, #FFF
│  │                                              Fill: #8B5CF6, corner 12, pad 16
│  │                                              Width: fill container
│
├─ Footer                                      ← EXACT name "Footer"
│  ├─ "No commitment · Cancel anytime"         ← Text: 11pt, #8E8E93, center
│  └─ FooterLinks                              ← HStack, spacing 16, center
│     ├─ Button(action=restore_purchases)      ← Contains text "Restore Purchases"
│     │  └─ "Restore Purchases"                ← Text: 11pt, #8E8E93
│     ├─ "·"                                   ← Text: 11pt, #8E8E93
│     ├─ Button(action=navigate_to)            ← Terms link (set URL post-import)
│     │  └─ "Terms"                            ← Text: 11pt, #8E8E93
│     ├─ "·"                                   ← Text: 11pt, #8E8E93
│     └─ Button(action=navigate_to)            ← Privacy link (set URL post-import)
│        └─ "Privacy"                          ← Text: 11pt, #8E8E93
```

---

## Package Component Details

Each package is a **Figma Component Set** named `Package` with a `State`
property having two variants: `Default` and `Selected`.

> **Important:** Create each package as a separate Component Set instance.
> After import, you assign which RC package ($rc_monthly, $rc_annual,
> $rc_lifetime) each one represents in the RC editor.

### Monthly Package

```
Package                                        ← Component Set
├─ State=Default                               ← HStack, pad 16, fill: #2C2C2E@80%, r12
│  ├─ Left                                     ← VStack, spacing 4, fill
│  │  └─ "Monthly"                             ← Text: 17pt bold, #FFF
│  └─ Right                                    ← VStack, align trailing, spacing 4
│     └─ "$1.99/month"                         ← Text: 15pt semibold, #FFF
│
└─ State=Selected                              ← Same as Default BUT:
   │                                              Stroke: 2px #8B5CF6, r12
   ├─ Left
   │  └─ "Monthly"
   └─ Right
      └─ "$1.99/month"
```

### Yearly Package

```
Package                                        ← Component Set
├─ State=Default                               ← HStack, pad 16, fill: #2C2C2E@80%, r12
│  ├─ Left                                     ← VStack, spacing 4, fill
│  │  ├─ "Yearly"                              ← Text: 17pt bold, #FFF
│  │  └─ "$0.83/mo"                            ← Text: 11pt, #8E8E93
│  └─ Right                                    ← VStack, align trailing, spacing 4
│     ├─ Badge                                 ← HStack, fill: #8B5CF6, capsule pad 8h 3v
│     │  └─ "SAVE 58%"                         ← Text: 10pt bold, #FFF
│     └─ "$9.99/year"                          ← Text: 15pt semibold, #FFF
│
└─ State=Selected                              ← Same + Stroke: 2px #8B5CF6
   ├─ Left
   │  ├─ "Yearly"
   │  └─ "$0.83/mo"
   └─ Right
      ├─ Badge → "SAVE 58%"
      └─ "$9.99/year"
```

### Lifetime Package

```
Package                                        ← Component Set
├─ State=Default                               ← HStack, pad 16, fill: #2C2C2E@80%, r12
│  ├─ Left                                     ← VStack, spacing 4, fill
│  │  ├─ "Lifetime"                            ← Text: 17pt bold, #FFF
│  │  └─ "Forever"                             ← Text: 11pt, #8E8E93
│  └─ Right                                    ← VStack, align trailing, spacing 4
│     ├─ Badge                                 ← HStack, fill: #8B5CF6, capsule pad 8h 3v
│     │  └─ "BEST VALUE"                       ← Text: 10pt bold, #FFF
│     └─ "$29.99 once"                         ← Text: 15pt semibold, #FFF
│
└─ State=Selected                              ← Same + Stroke: 2px #8B5CF6
   ├─ Left
   │  ├─ "Lifetime"
   │  └─ "Forever"
   └─ Right
      ├─ Badge → "BEST VALUE"
      └─ "$29.99 once"
```

---

## Notes

### What's NOT supported by the Figma plugin (configure post-import)

- **Switch / Trial Toggle** — Not supported for import. Add in the RC
  editor after import using the Switch component.
- **Countdown timers** — Not supported for import.
- **Dynamic price variables** — Replace hardcoded "$1.99" etc. with RC
  variables (`{{ price }}`) in the editor post-import.

### Post-Import Checklist

1. Open imported paywall in RC editor
2. Assign packages: click each Package → assign `$rc_monthly`, `$rc_annual`, `$rc_lifetime`
3. Replace hardcoded prices with RC variables (e.g., `{{ price }}/{{ sub_period }}`)
4. Set Button URLs: Terms → `https://vaultaire.app/terms`, Privacy → `https://vaultaire.app/privacy`
5. Add Switch component above Purchase Button for trial toggle (if desired)
6. Set branding colors in Branding tab
7. Preview on device
8. Publish

### Typography Reference (iOS system equivalents)

| Figma Setting      | iOS Equivalent  |
|--------------------|-----------------|
| 28pt SF Pro Bold   | .title.bold()   |
| 17pt SF Pro Bold   | .headline       |
| 15pt SF Pro Regular| .subheadline    |
| 11pt SF Pro Medium | .caption        |
| 10pt SF Pro Bold   | .caption2.bold()|
