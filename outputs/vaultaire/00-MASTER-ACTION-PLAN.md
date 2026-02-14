# Vaultaire ASO Master Action Plan

**App:** Vaultaire: Encrypted Vault (app.vaultaire.ios)
**Platform:** Apple App Store
**Target Launch:** March 5, 2026 (Thursday)
**Current State:** Build 15 on TestFlight, feature-complete
**Generated:** February 12, 2026

---

## Key Insight

> **"Encrypted" is an uncontested keyword.** Among 180+ photo vault apps analyzed, ZERO use "encrypted" in their title. Every competitor competes on "hiding" -- Vaultaire competes on *real security*. This is a category of one.

---

## Copy-Paste Metadata (Ready Now)

| Field | Value | Chars |
|-------|-------|-------|
| **Title** | `Vaultaire: Encrypted Vault` | 26/30 |
| **Subtitle** | `Private Photo & File Storage` | 29/30 |
| **Keywords** | `photo vault,encrypted,private,secure photos,hide,privacy,file vault,encryption,duress,secret vault` | 99/100 |
| **Promo Text** | See `02-metadata/apple-metadata.md` | 166/170 |

Full description (3,247 chars), What's New, and 2 A/B test variants in `02-metadata/apple-metadata.md`.

---

## 21-Day Launch Countdown

### Week 1: Feb 12-18 -- Metadata & Legal
| Day | Date | Action | Status |
|-----|------|--------|--------|
| Thu | Feb 12 | Review this plan, confirm launch date | [ ] |
| Thu | Feb 12 | Metadata drafts complete (DONE -- see 02-metadata/) | [x] |
| Fri | Feb 13 | Finalize metadata, enter into App Store Connect | [ ] |
| Sat-Sun | Feb 14-15 | Draft privacy policy and terms of service | [ ] |
| Mon | Feb 16 | Publish privacy policy at vaultaire.app/privacy | [ ] |
| Mon | Feb 16 | Publish terms at vaultaire.app/terms | [ ] |
| Tue | Feb 17 | Complete App Privacy nutrition label in ASC | [ ] |
| Tue | Feb 17 | Complete encryption export compliance (ECCN 5D992.c) | [ ] |
| Wed | Feb 18 | Enter all metadata into ASC, internal proofread | [ ] |

### Week 2: Feb 19-25 -- Visual Assets & Final Build
| Day | Date | Action | Status |
|-----|------|--------|--------|
| Thu | Feb 19 | Design screenshot templates (see visual-assets-spec.md) | [ ] |
| Fri | Feb 20 | Create screenshots: 6.7", 6.5", 5.5" displays | [ ] |
| Sat-Sun | Feb 21-22 | Buffer / optional app preview video | [ ] |
| Mon | Feb 23 | Upload screenshots + icon to ASC | [ ] |
| Tue | Feb 24 | Build 16: bump, test, archive, upload to ASC | [ ] |
| Wed | Feb 25 | Write App Review notes (CRITICAL -- see below) | [ ] |

### Week 3: Feb 26 - Mar 5 -- Submit & Launch
| Day | Date | Action | Status |
|-----|------|--------|--------|
| Thu | Feb 26 | **SUBMIT TO APP REVIEW** (manual release) | [ ] |
| Fri-Mon | Feb 27-Mar 2 | Monitor review, respond same-day if needed | [ ] |
| Tue | Mar 3 | Verify "Pending Developer Release" state | [ ] |
| Wed | Mar 4 | Final go/no-go, prep launch announcements | [ ] |
| **Thu** | **Mar 5** | **LAUNCH: Release on App Store at 9 AM** | [ ] |

---

## App Review Notes (Pre-Written)

> **Copy this into App Store Connect > App Review Information > Notes:**
>
> Vaultaire is a personal encrypted photo and file vault. It uses Apple's CryptoKit framework (AES-256-GCM) and Secure Enclave (Security framework) for hardware-backed encryption.
>
> **How to test:** Draw any pattern connecting 6+ dots to create your vault. Import photos from the gallery or take new ones with the camera. Files are encrypted immediately upon import.
>
> **Duress vault feature:** A secondary unlock pattern opens a separate decoy vault. This is a personal safety feature for individuals who may face pressure to reveal vault contents (e.g., journalists, activists, domestic abuse survivors). It does not facilitate hiding illegal content.
>
> **No account required:** The app works fully offline with no sign-up. Optional iCloud encrypted backup uses the user's own iCloud account.
>
> **Encryption compliance:** Uses AES-256-GCM via Apple CryptoKit. Qualifies for License Exception ENC under ECCN 5D992.c (mass market encryption).

---

## Top 5 Competitive Advantages

| # | Advantage | Competitors Have It? |
|---|-----------|---------------------|
| 1 | **AES-256-GCM encryption** (not just app lock) | 0/8 top competitors |
| 2 | **Secure Enclave hardware keys** | 0/8 top competitors |
| 3 | **Duress vault** (fake vault under coercion) | 0/8 top competitors |
| 4 | **No account required** (fully offline) | 1/8 (most require accounts) |
| 5 | **Streaming encryption** (memory efficient) | 0/8 top competitors |

---

## Screenshot Strategy (6 screens)

| # | Content | Headline |
|---|---------|----------|
| 1 | Pattern lock screen | "Your Vault. Your Keys." |
| 2 | Encrypted vault grid | "Real Encryption, Not Just a Lock" |
| 3 | Secure Enclave callout | "Hardware-Protected Security" |
| 4 | Duress vault feature | "Show a Fake Vault Under Pressure" |
| 5 | Shared encrypted vault | "Share Securely with Anyone" |
| 6 | Recovery phrase | "No Account. No Tracking. Ever." |

Full spec in `02-metadata/visual-assets-spec.md`.

---

## Post-Launch Optimization Schedule

| Timeframe | Action |
|-----------|--------|
| **Daily** (15 min) | Check reviews, respond within 24h, monitor Sentry crashes |
| **Weekly** (1 hr) | Keyword rankings, conversion rate, competitor check |
| **Week 3** | First A/B test: icon variants |
| **Week 5** | Screenshot A/B test |
| **Month 2** | Subtitle A/B test, keyword field iteration |
| **Month 3** | Localization (Japanese, Korean, German, French, Spanish) |
| **Month 6** | Apple Search Ads campaign, editorial pitch |

Full schedule in `05-optimization/ongoing-tasks.md`.
Review response templates in `05-optimization/review-responses.md`.

---

## Rejection Risk & Mitigation

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| "App facilitates hiding content" | Medium | Review notes emphasize security/privacy, not hiding. Reference approved competitors. |
| Export compliance rejection | Low | ECCN 5D992.c documented, uses Apple frameworks only |
| "Hidden features" concern | Low | All features discoverable, duress vault explained in notes |
| Missing demo account | Low | App requires no account -- explained in review notes |

Pre-written rejection responses in `04-launch/submission-guide.md`.

---

## File Index

```
outputs/vaultaire/
├── 00-MASTER-ACTION-PLAN.md          << YOU ARE HERE
├── 01-research/
│   ├── keyword-list.md                27 keywords, 15 long-tail, copy-paste keyword field
│   ├── competitor-gaps.md             8 competitors analyzed, 12 feature gaps identified
│   ├── action-research.md             Research phase checklist
│   └── raw-data/                      23 iTunes API JSON files (4.4 MB)
├── 02-metadata/
│   ├── apple-metadata.md              Copy-paste ready metadata, all chars validated
│   ├── visual-assets-spec.md          Icon + screenshot specs and strategy
│   └── action-metadata.md             Metadata implementation tasks
├── 03-testing/
│   ├── ab-test-setup.md               6 A/B tests planned with setup instructions
│   └── action-testing.md              Testing calendar and action items
├── 04-launch/
│   ├── prelaunch-checklist.md         48-item checklist across 7 phases
│   ├── timeline.md                    Day-by-day schedule Feb 12 → Apr 2
│   ├── submission-guide.md            ASC setup + rejection response templates
│   └── action-launch.md              Launch day hour-by-hour execution plan
└── 05-optimization/
    ├── review-responses.md            18 response templates by category
    ├── ongoing-tasks.md               Daily/weekly/monthly optimization schedule
    └── action-optimization.md         Priority-ordered optimization roadmap
```

---

## Next Steps (Today)

1. **Review this plan** and confirm March 5 launch target
2. **Enter metadata** into App Store Connect (copy from `02-metadata/apple-metadata.md`)
3. **Start privacy policy** draft for vaultaire.app/privacy
4. **File encryption export compliance** (ECCN 5D992.c self-classification)

The metadata is ready to paste. The biggest remaining work is **screenshots** (design needed by Feb 20) and **legal** (privacy policy by Feb 16).
