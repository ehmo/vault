# Vaultaire ASO Master Action Plan

**App:** Vaultaire: Encrypted Vault (id6740526623 / app.vaultaire.ios)
**Platform:** Apple App Store (iOS only)
**Status:** Live on App Store
**Audit Date:** February 17, 2026
**Previous Audit:** February 12, 2026

---

## Audit Summary

This is an updated comprehensive ASO audit for Vaultaire, building on the initial Feb 12 research. The app is now live on the App Store. This plan shifts focus from pre-launch preparation to **post-launch optimization and growth**.

---

## Key Insight

> **"Encrypted" is an uncontested keyword.** Among 180+ photo vault apps analyzed, ZERO use "encrypted" in their title. Every competitor competes on "hiding" -- Vaultaire competes on *real security*. This is a category of one.

> **Critical finding (Feb 17 update):** The app does not appear in iTunes Search API results for "vaultaire" or by its App Store ID. This indicates either very recent launch with incomplete indexing, or potential search visibility issues that need investigation. Action item added below.

---

## Immediate Action Items (This Week: Feb 17-23)

### Priority 0: Verify Search Visibility
- [ ] Search the App Store on your device for "Vaultaire" -- does the app appear?
- [ ] Search for "encrypted vault" -- does it appear?
- [ ] Verify the direct link works: https://apps.apple.com/app/id6740526623
- [ ] If the app does not appear in search after 7+ days live, contact Apple Developer Support
- [ ] Check App Store Connect > Analytics > Sources to see if search impressions exist

### Priority 1: Confirm Current Live Metadata
- [ ] Log in to App Store Connect and verify what is currently live:
  - Current title (should be: "Vaultaire: Encrypted Vault")
  - Current subtitle
  - Current keyword field
  - Current description
  - Current promotional text
- [ ] Compare live metadata against recommendations in `02-metadata/apple-metadata.md`
- [ ] Note any differences and decide which to update in next submission

### Priority 2: Metadata Optimization (If Not Already Applied)
If the optimized metadata from `02-metadata/apple-metadata.md` has NOT been applied:
- [ ] Update keyword field to the recommended 99-char version (see Quick Reference below)
- [ ] Update subtitle to recommended version
- [ ] Update promotional text (can be changed without app submission)
- [ ] Update description to the optimized 3,247-char version

### Priority 3: Start Baseline Tracking
- [ ] Record this week's App Store Connect metrics:
  - Impressions: ___
  - Product Page Views: ___
  - App Units (downloads): ___
  - Conversion Rate: ___%
- [ ] Search for 10 target keywords and record positions (see ongoing-tasks.md)
- [ ] Set calendar reminder: weekly Monday keyword tracking

---

## Copy-Paste Metadata (Ready Now)

| Field | Value | Chars |
|-------|-------|-------|
| **Title** | `Vaultaire: Encrypted Vault` | 26/30 |
| **Subtitle** | `Private Photo & File Locker` | 27/30 |
| **Keywords** | `secret,hide,photos,lock,album,safe,hidden,secure,videos,gallery,backup,AES,password,privacy,encrypt` | 99/100 |

**Important keyword field notes:**
- NO spaces after commas
- Do NOT include words already in title/subtitle (vault, encrypted, private, photo, file, locker)
- Apple combines individual words, so "secret" + "photos" covers "secret photos" searches
- The research-derived keyword field above is optimized for maximum coverage

**Promotional Text** (166/170 chars, updatable without submission):
See `02-metadata/apple-metadata.md` for copy-paste ready text.

Full description (3,247 chars) with 2 A/B test variants in `02-metadata/apple-metadata.md`.

---

## Top 5 Competitive Advantages

| # | Advantage | Competitors Have It? |
|---|-----------|---------------------|
| 1 | **AES-256-GCM encryption** (not just app lock) | 0/8 top competitors |
| 2 | **Secure Enclave hardware keys** | 0/8 top competitors |
| 3 | **Duress vault** (fake vault under coercion) | 0/8 top competitors |
| 4 | **No account required** (fully offline) | 1/8 (most require accounts) |
| 5 | **Encrypted sharing via CloudKit** | 0/8 top competitors |

---

## Optimization Phases (Post-Launch)

### Phase 1: Foundation (Weeks 1-2 Post-Launch) -- NOW
**Focus:** Establish baseline, fix any metadata gaps
**See:** `01-research/action-research.md`, `02-metadata/action-metadata.md`

- [ ] Verify search visibility (Priority 0 above)
- [ ] Confirm all metadata is applied and correct
- [ ] Collect baseline metrics for 2 full weeks
- [ ] Respond to every review within 24 hours
- [ ] Monitor Sentry for crashes daily

**Time Estimate:** 15 min/day + 2 hours one-time setup
**Dependencies:** App Store Connect access
**Deliverable:** Baseline metrics spreadsheet

---

### Phase 2: First Iteration (Weeks 3-4)
**Focus:** Data-driven metadata adjustments
**See:** `05-optimization/action-optimization.md`

- [ ] Analyze 2-week baseline data
- [ ] Identify underperforming keywords (no ranking after 2 weeks)
- [ ] Replace weak keywords with new candidates
- [ ] Update promotional text based on early feedback
- [ ] If CVR below 5%: redesign Screenshot 1

**Time Estimate:** 3-4 hours total
**Dependencies:** Phase 1 baseline data
**Deliverable:** Updated keyword field, revised promotional text

---

### Phase 3: A/B Testing (Weeks 5-8)
**Focus:** Icon and screenshot optimization via Product Page Optimization
**See:** `03-testing/ab-test-setup.md`, `03-testing/action-testing.md`

- [ ] Design 2 alternative app icons
- [ ] Set up icon A/B test in PPO (33/33/33 traffic split)
- [ ] Run for 14 days minimum
- [ ] Implement winning icon
- [ ] Then test Screenshot 1 headline variants

**Time Estimate:** 6-8 hours design + 5 min/day monitoring
**Dependencies:** 10,000+ weekly impressions minimum
**Deliverable:** Winning icon and screenshot variants

---

### Phase 4: Growth (Months 2-3)
**Focus:** Subtitle testing, review velocity, advanced optimization
**See:** `05-optimization/action-optimization.md`

- [ ] Test subtitle variant via app update
- [ ] Implement SKStoreReviewController (smart prompt)
- [ ] Target: 50+ ratings by end of month 3
- [ ] Evaluate Apple Search Ads ($5-10/day)
- [ ] Monthly competitor refresh

**Time Estimate:** 2-3 hours/week
**Dependencies:** Phase 3 results
**Deliverable:** Optimized subtitle, growing review count

---

### Phase 5: Scale (Months 3-6)
**Focus:** Localization, Custom Product Pages, editorial pitch
**See:** `05-optimization/action-optimization.md`

- [ ] Localize metadata: Japanese, Korean, German, French, Spanish
- [ ] Create 2-3 Custom Product Pages for different audiences
- [ ] Pitch to App Store editorial (when 100+ reviews, 4.5+ rating)
- [ ] Quarterly keyword research refresh

**Time Estimate:** 20-30 hours total
**Dependencies:** 100+ reviews, stable metrics
**Deliverable:** Multi-language listing, CPP pages

---

## Ongoing Schedule

| Cadence | Activity | Time |
|---------|----------|------|
| **Daily** (15 min) | Check reviews, respond within 24h, monitor crashes | 15 min |
| **Weekly** (1 hr, Monday) | Keyword rankings, conversion rate, competitor check | 1 hr |
| **Bi-weekly** (1 hr) | Metadata performance review, screenshot effectiveness | 1 hr |
| **Monthly** (2-3 hr) | Comprehensive metrics, keyword strategy, competitor deep dive | 2-3 hr |
| **Quarterly** (4-6 hr) | Full keyword refresh, market positioning, visual overhaul | 4-6 hr |

Full schedule in `05-optimization/ongoing-tasks.md`.
Review response templates in `05-optimization/review-responses.md`.

---

## Known Issues and Inconsistencies (Fixed in This Update)

1. **Keyword field conflict resolved:** Research file recommended single-word keywords (99 chars); metadata file had multi-word phrases. Single-word approach is correct for Apple (Apple combines words automatically). The research-derived field is the recommended one.

2. **Subtitle standardized:** Multiple files had different subtitle recommendations. Standardized to "Private Photo & File Locker" (27 chars) which covers "photo," "file," and "locker" keywords.

3. **Category recommendation clarified:** Primary should be **Utilities** (less direct competition with Photo & Video mega-apps, aligns with encryption/security positioning). Secondary should be **Photo & Video** (captures photo-related searches). This matches the submission guide rationale.

4. **Timeline updated:** All dates updated from the pre-launch March 5 timeline to reflect current live status as of Feb 17, 2026.

---

## File Index

```
outputs/vaultaire/
├── 00-MASTER-ACTION-PLAN.md          << YOU ARE HERE
├── 01-research/
│   ├── keyword-list.md                27 keywords, 15 long-tail, copy-paste keyword field
│   ├── competitor-gaps.md             8 competitors analyzed, 12 feature gaps identified
│   ├── action-research.md             Research phase checklist
│   └── raw-data/                      23 iTunes API JSON files
├── 02-metadata/
│   ├── apple-metadata.md              Copy-paste ready metadata, all chars validated
│   ├── visual-assets-spec.md          Icon + screenshot specs and strategy
│   └── action-metadata.md             Metadata implementation tasks
├── 03-testing/
│   ├── ab-test-setup.md               6 A/B tests planned with setup instructions
│   └── action-testing.md              Testing calendar and action items
├── 04-launch/
│   ├── prelaunch-checklist.md          48-item checklist across 7 phases
│   ├── timeline.md                    Day-by-day schedule (historical, pre-launch)
│   ├── submission-guide.md            ASC setup + rejection response templates
│   ├── encryption-compliance.md       ECCN 5D992.c classification + BIS filing
│   ├── bis-self-classification.csv    Pre-filled BIS report
│   └── action-launch.md              Launch day execution plan (historical)
└── 05-optimization/
    ├── review-responses.md            18 response templates by category
    ├── ongoing-tasks.md               Daily/weekly/monthly optimization schedule
    └── action-optimization.md         Priority-ordered optimization roadmap
```

---

## Next Steps (Today)

1. **Verify search visibility** -- Search for "Vaultaire" on your device's App Store
2. **Confirm live metadata** -- Log in to App Store Connect and compare against recommendations
3. **Update promotional text** -- Can be done immediately without app submission
4. **Start tracking keywords** -- Search for 10 target keywords, record positions
5. **Set up weekly monitoring** -- Calendar reminder for Monday keyword/metrics check

The biggest quick wins right now are:
- **Promotional text update** (no submission needed, immediate impact on conversion)
- **Keyword field optimization** (if not already using the single-word optimized version)
- **Review responses** (respond to every review within 24 hours using templates)
