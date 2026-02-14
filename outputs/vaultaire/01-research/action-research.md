# Research Action Checklist - Vaultaire: Encrypted Vault

**Date:** 2026-02-12
**Status:** Research complete. Ready for metadata optimization phase.

---

## Phase 1: Review Research Outputs (Est: 30 min)

- [ ] Read `keyword-list.md` completely
- [ ] Identify top 5 keywords for title/subtitle placement
- [ ] Confirm title: `Vaultaire: Encrypted Vault` (26 chars)
- [ ] Confirm subtitle choice from options:
  - Option A: `Private Photo & File Locker` (27 chars)
  - Option B: `Secure Photo Vault & File Lock` (30 chars)
  - Option C: (custom)
- [ ] Read `competitor-gaps.md` completely
- [ ] Note the 12 CRITICAL gaps to emphasize in messaging
- [ ] Validate keyword field (100 chars) -- add/remove terms as needed

---

## Phase 2: Keyword Field Implementation (Est: 30 min)

- [ ] Finalize Apple Keyword Field (100 chars max, comma-separated, no spaces):
  ```
  secret,hide,photos,lock,album,safe,hidden,secure,videos,gallery,backup,AES,password,privacy,encrypt
  ```
- [ ] Verify no keyword duplicates title or subtitle words
- [ ] Verify total character count is within 100
- [ ] Consider localization priority:
  - [ ] Japanese (high vault app usage in Japan per competitor data)
  - [ ] Korean (Private Photo Vault is top-100 in Korea)
  - [ ] German
  - [ ] French

---

## Phase 3: Category Selection (Est: 10 min)

- [ ] Select Primary Category: **Photo & Video** (5/8 competitors use this)
- [ ] Select Secondary Category: **Utilities** (6/8 competitors use this)
- [ ] Verify these categories are available in App Store Connect
- [ ] Note: Competitors in Utilities get less Photo-related search traffic

---

## Phase 4: Description & Promotional Text Planning (Est: 1 hour)

### Promotional Text (170 chars, updatable without app review)
- [ ] Draft promotional text leading with encryption differentiator
- [ ] Suggested draft:
  ```
  The only photo vault with real AES-256 encryption and Secure Enclave protection.
  Hide photos, videos & files behind military-grade security that actually works.
  ```
  (163 chars)

### Description (4000 chars, requires app review)
- [ ] Plan description structure:
  1. **Opening hook** -- encryption differentiator (first 3 lines visible before "more")
  2. **Feature list** -- bullet points, keyword-rich
  3. **How it works** -- brief technical credibility section
  4. **Use cases** -- specific scenarios (following Keepsafe's approach)
  5. **Privacy commitment** -- no tracking, no access to your data
  6. **Subscription details** -- required by Apple
- [ ] Include these differentiation keywords naturally:
  - "AES-256-GCM encryption"
  - "Secure Enclave"
  - "end-to-end encrypted"
  - "duress vault"
  - "shared encrypted vaults"
  - "iCloud encrypted backup"
  - "recovery phrase"
  - "zero-knowledge"
- [ ] Include these high-volume keywords for conversion:
  - "photo vault"
  - "hide photos"
  - "private"
  - "secure"
  - "lock"
  - "secret"
  - "password"
  - "Face ID"

---

## Phase 5: Competitive Differentiation Messaging (Est: 30 min)

- [ ] Define 3 headline differentiators for App Store screenshots:
  1. "Real AES-256 Encryption" (vs. competitors' vague "secure" claims)
  2. "Secure Enclave Protected" (hardware security -- no competitor has this)
  3. "Share Encrypted Vaults" (unique feature -- no competitor offers this)
- [ ] Plan comparison messaging (use carefully -- Apple has guidelines):
  - "Unlike apps that just hide your photos, Vaultaire encrypts them"
  - "Your photos are encrypted, not just hidden"
- [ ] Decide on ad-free positioning (if applicable)
- [ ] Plan duress vault messaging:
  - Consider using "panic mode" or "decoy vault" (more searchable) alongside "duress vault" (more unique)

---

## Phase 6: Apple Search Ads Preparation (Est: 30 min)

- [ ] Compile target keyword list for Apple Search Ads campaigns:
  - **Brand defense:** "vaultaire"
  - **Category terms:** "photo vault," "secret photos," "private vault"
  - **Competitor terms:** "keepsafe," "private photo vault" (allowed in Search Ads)
  - **Differentiator terms:** "encrypted photos," "AES vault," "secure enclave photos"
- [ ] Set budget priorities:
  - Highest ROI: Long-tail encrypted terms (low competition, high intent)
  - Highest volume: "photo vault," "hide photos" (expensive but high traffic)
  - Brand conquest: Competitor names (moderate cost, high conversion if differentiated)
- [ ] Plan Search Ads Creative Sets to match keyword themes

---

## Phase 7: Monitoring & Iteration Setup (Est: 30 min)

- [ ] Bookmark competitor App Store pages for manual monitoring:
  - https://apps.apple.com/us/app/id417571834 (Private Photo Vault)
  - https://apps.apple.com/us/app/id510873505 (Keepsafe)
  - https://apps.apple.com/us/app/id1449239240 (SPV)
  - https://apps.apple.com/us/app/id1165276801 (Calculator#)
  - https://apps.apple.com/us/app/id488030828 (Best Secret Folder)
  - https://apps.apple.com/us/app/id1186436980 (Privault)
- [ ] Schedule monthly competitor check:
  - Title/subtitle changes
  - Rating changes
  - New features added
  - New competitors entering market
- [ ] Plan keyword ranking tracking:
  - Manual: Search App Store for target keywords, note position
  - Tool-based: Consider AppFollow, Sensor Tower, or AppTweak trial
- [ ] Set up review monitoring for competitor weakness signals

---

## Phase 8: Pre-Launch Validation (Est: 1 hour)

- [ ] Verify App Store Connect metadata fields are within limits:
  - Title: 30 chars
  - Subtitle: 30 chars
  - Keywords: 100 chars
  - Description: 4000 chars
  - Promotional text: 170 chars
- [ ] Test search visibility after submission:
  - Search for "Vaultaire" (brand)
  - Search for "encrypted vault" (differentiator)
  - Search for "photo vault" (category)
  - Search for "private photo locker" (subtitle keywords)
- [ ] Review Apple's ASO guidelines for compliance:
  - No competitor names in keywords
  - No misleading claims
  - No keyword stuffing in title
- [ ] Prepare day-1 promotional text emphasizing launch features

---

## Validation Criteria

Before marking research phase complete, verify:

- [x] At least 10 primary keywords identified (27 keywords across 3 tiers)
- [x] At least 3 competitors analyzed (8 primary + 6 secondary = 14 total)
- [x] Real data fetched (iTunes API: 23 searches, 180+ unique apps)
- [x] Search volume estimates documented with methodology
- [x] Competition levels assessed with real data
- [x] Clear implementation locations for each keyword
- [x] Competitive gaps documented (12 CRITICAL gaps found)
- [x] Keyword field ready for copy-paste (99 chars)
- [x] Title and subtitle recommendations with character counts
- [x] Category recommendation based on competitor data

---

## Quality Self-Assessment

| Dimension | Score | Notes |
|-----------|-------|-------|
| Data Quality | 4.5/5 | Real iTunes API data. Missing exact search volumes (would need Apple Search Ads). |
| Actionability | 5/5 | Copy-paste keyword field, specific title/subtitle, char counts. |
| Completeness | 5/5 | 8 competitors deep-analyzed, 23 keyword searches, 180+ apps. |
| Relevance | 5/5 | All keywords directly relevant to Vaultaire's features. |

**Overall: 4.9/5**

---

## Key Findings Summary

1. **"Encrypted" is the single most valuable keyword gap.** Zero competitors use it in their title. Combined with "vault," it creates a unique and defensible position.

2. **The photo vault market competes on hiding, not security.** Vaultaire's real encryption (AES-256-GCM, Secure Enclave) is a genuine technical differentiator that no competitor can match without a major rewrite.

3. **Shared encrypted vaults and duress vault are unique features** with zero competitive presence. These should be prominently featured in description and screenshots.

4. **Category choice matters.** Photo & Video (primary) + Utilities (secondary) matches where users search and where competitors rank.

5. **Long-tail encryption keywords are Vaultaire's blue ocean.** Terms like "encrypted photo vault," "AES photo vault," and "secure enclave vault" have low competition and attract high-intent security-conscious users.

---

## Next Steps

**Immediate:** Hand off to ASO metadata optimization phase
- Use `keyword-list.md` for keyword field and title/subtitle
- Use `competitor-gaps.md` for description and promotional text strategy
- Generate App Store description, screenshots text, and promotional text

**Week 1 post-launch:**
- Monitor keyword ranking for top 10 target terms
- Track download conversion rate
- Adjust promotional text (no review needed) based on early data

**Month 1:**
- Re-run competitor analysis (refresh iTunes API data)
- Evaluate Apple Search Ads performance
- Consider A/B testing subtitle variants
