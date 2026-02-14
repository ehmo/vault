# Ongoing Optimization Action Items -- Vaultaire

**Purpose:** Prioritized action items for continuous App Store Optimization after launch. These are strategic improvements to execute beyond daily/weekly maintenance.

---

## Priority 1: First 30 Days Post-Launch (March 5 - April 4, 2026)

### Action 1.1: Establish Keyword Baseline
**When:** March 5-12 (launch week)
**Effort:** 2 hours
**Impact:** Foundation for all future keyword optimization

- [ ] Search App Store for all 15 target keywords and record Vaultaire's position
- [ ] Record positions of top 3 competitors for each keyword
- [ ] Identify which keywords Vaultaire appears on page 1 (top 10) vs page 2+ (11-50) vs not visible (50+)
- [ ] Create a tracking spreadsheet with columns: keyword, position, impressions, date
- [ ] Set weekly reminder to update positions every Monday

### Action 1.2: Screenshot Conversion Optimization
**When:** March 12-19 (after first week of data)
**Effort:** 4-6 hours
**Impact:** High -- screenshots are the primary conversion driver

- [ ] Analyze impression-to-page-view ratio in ASC Analytics
  - Above 8%: screenshots are compelling, people tap to learn more
  - Below 5%: first screenshot is not compelling enough
- [ ] If below target, redesign first 2 screenshots with:
  - Larger, bolder text overlays
  - More contrast with competitor screenshots in search results
  - Focus on "AES-256 Encrypted" as a differentiation callout
- [ ] Submit with next app update

### Action 1.3: First Metadata Iteration
**When:** March 19-26 (after two weeks of data)
**Effort:** 2 hours
**Impact:** Medium-high -- keywords drive search visibility

- [ ] Identify underperforming keywords (no ranking improvement after 2 weeks)
- [ ] Replace with new keyword candidates from analysis
- [ ] Update promotional text to reflect early user feedback and feature highlights
- [ ] Submit keyword changes with v1.1 update

### Action 1.4: Review Velocity Strategy
**When:** Ongoing from launch
**Effort:** 15 min/day
**Impact:** High -- reviews affect ranking and conversion

- [ ] Respond to every review within 24 hours
- [ ] For 1-2 star reviews with fixable issues: fix the issue, respond noting the fix, hope for rating update
- [ ] Consider implementing SKStoreReviewController after a positive interaction:
  - After successful first photo import (user has invested in the app)
  - After 7 days of use with 3+ opens
  - NOT immediately after launch, NOT after errors
  - Maximum 3 prompts per 365-day period (Apple's limit)
- [ ] Target: 10+ ratings in first month

---

## Priority 2: Days 30-90 (April - June 2026)

### Action 2.1: Product Page Optimization (PPO) A/B Testing
**When:** April 2026 (need sufficient traffic first)
**Effort:** 4 hours to set up, 2 weeks to run
**Impact:** High -- data-driven optimization

Apple's Product Page Optimization allows testing up to 3 treatments against the default:

**Test 1: Icon** (if conversion below target)
- Treatment A: Current icon
- Treatment B: Icon with more visible lock/shield imagery
- Treatment C: Icon with brighter color palette
- Run for 14 days or until statistically significant

**Test 2: Screenshots** (most impactful test)
- Treatment A: Current screenshot order
- Treatment B: Lead with "AES-256 Encrypted" security callout
- Treatment C: Lead with vault grid showing photos (emotional appeal)
- Run for 14 days or until statistically significant

**Test 3: Subtitle** (requires app update to change)
- Test different subtitle approaches:
  - Security-focused: "AES-256 Encrypted Photo Vault"
  - Feature-focused: "Private Photo & Video Lock"
  - Benefit-focused: "Hide & Encrypt Your Photos"

### Action 2.2: Description Optimization
**When:** April 2026
**Effort:** 3 hours
**Impact:** Medium -- affects conversion for users who scroll to read

- [ ] Analyze which features users mention most in reviews
- [ ] Restructure description to lead with most-appreciated features
- [ ] Add a "How It Works" section explaining encryption in simple terms
- [ ] Add a "Why Vaultaire?" comparison section (without naming competitors)
- [ ] A/B test long-form description vs concise bullet-point format

### Action 2.3: Competitor Response Strategy
**When:** Monthly monitoring
**Effort:** 1 hour/month
**Impact:** Defensive -- prevents competitors from outmaneuvering

- [ ] Set calendar reminder to check competitor updates monthly
- [ ] If a competitor adds a feature Vaultaire has: update metadata to highlight it
- [ ] If a competitor gets negative reviews for something Vaultaire does better: reference in promotional text
- [ ] If a new competitor enters the space: analyze their keywords and differentiation

### Action 2.4: In-App Review Prompt Implementation
**When:** v1.2 update (April 2026)
**Effort:** 2 hours (code) + 1 hour (strategy)
**Impact:** High -- organic review generation is critical for new apps

Implementation plan:
```swift
// Trigger conditions (all must be true):
// 1. User has been using app for 7+ days
// 2. User has imported 5+ files (invested in the app)
// 3. User has opened the app 3+ times this week (active user)
// 4. No recent errors or crashes
// 5. Hasn't been prompted in last 120 days

import StoreKit
SKStoreReviewController.requestReview(in: windowScene)
```

- [ ] Implement smart review prompt with conditions above
- [ ] Track prompt count (Apple limits to 3 per year)
- [ ] Never prompt during or immediately after an error
- [ ] Never prompt during import (user is busy)
- [ ] Prompt after a satisfying interaction (e.g., after unlocking vault, viewing an album)

---

## Priority 3: Days 90-180 (June - September 2026)

### Action 3.1: Localization (Highest ROI Growth Lever)
**When:** June 2026
**Effort:** 20-30 hours (across all languages)
**Impact:** Very high -- multiplies addressable market

Phase 1 -- Metadata only (low effort, high impact):
- [ ] Translate title, subtitle, keywords, description for:
  - Japanese (large iOS market, high privacy awareness)
  - Korean (large iOS market)
  - German (strong privacy culture, large European market)
  - Spanish (large aggregate market)
  - French (significant iOS market)
- [ ] Use professional translators familiar with ASO (not just bilingual)
- [ ] Each language needs keyword research specific to that market (direct translation of English keywords often misses better local alternatives)

Phase 2 -- Screenshots (medium effort):
- [ ] Translate screenshot text overlays for Phase 1 languages
- [ ] Adapt messaging for cultural context if needed

Phase 3 -- In-app localization (high effort, do only if Phase 1 shows results):
- [ ] Localize app UI strings
- [ ] Test with native speakers
- [ ] Submit localized builds

### Action 3.2: Custom Product Pages (CPP)
**When:** July 2026
**Effort:** 6-8 hours
**Impact:** Medium-high -- enables targeted messaging for different audiences

Apple allows up to 35 custom product pages. Create targeted pages for:

**Page 1: Privacy Advocates**
- Screenshots emphasizing: zero-knowledge design, no accounts, no tracking
- Description focused on privacy philosophy
- Keywords: privacy, no tracking, zero knowledge

**Page 2: Security Professionals**
- Screenshots emphasizing: AES-256-GCM, Secure Enclave, encryption details
- Description focused on technical security
- Keywords: encryption, AES-256, Secure Enclave, journalist

**Page 3: General Consumers**
- Screenshots emphasizing: easy to use, pattern lock, photo organization
- Description focused on simplicity and peace of mind
- Keywords: photo lock, private photos, hide pictures

Use these with targeted ad campaigns or specific referral URLs.

### Action 3.3: Apple Search Ads (Paid Acquisition)
**When:** July 2026 (after organic baseline established)
**Effort:** 2 hours setup, 30 min/week management
**Impact:** Medium -- accelerates growth but requires budget

Strategy:
- [ ] Start with Search Results campaigns (highest intent)
- [ ] Target competitor brand keywords: "keepsafe", "private photo vault"
  - Bid conservatively -- these are expensive but high-intent
- [ ] Target category keywords: "photo vault", "encrypted photos"
  - These are your core organic targets; ads accelerate ranking
- [ ] Set daily budget: $5-10/day initially
- [ ] Track Cost Per Acquisition (CPA) -- target under $2 for a free app
- [ ] Monitor which keywords convert best and increase organic focus on those
- [ ] Use Custom Product Pages for different keyword groups

---

## Priority 4: Days 180-365 (September 2026 - March 2027)

### Action 4.1: Category Ranking Push
**When:** September 2026 (iOS launch season)
**Effort:** Ongoing
**Impact:** High -- category ranking is a major visibility driver

Tactics:
- [ ] Time a major feature update for September (iOS launch month = highest App Store traffic)
- [ ] Optimize for the new iOS version features immediately
- [ ] Push for reviews around the update (SKStoreReviewController prompt)
- [ ] Consider temporary pricing promotion to boost download volume

### Action 4.2: App Store Editorial Pitch
**When:** When the app has 4.5+ rating and 100+ reviews
**Effort:** 4 hours
**Impact:** Very high if featured (can drive 10-100x normal downloads)

- [ ] Apply via Apple's self-submission form: https://developer.apple.com/contact/app-store/promote/
- [ ] Pitch angle: "Privacy-first photo vault using genuine AES-256-GCM encryption and Secure Enclave -- a real security app in a category full of fake vaults"
- [ ] Highlight: no account required, duress vault for at-risk individuals, end-to-end encrypted sharing
- [ ] Include metrics: rating, reviews, crash-free rate
- [ ] Best timing: around a privacy-related news event or iOS feature launch

### Action 4.3: Annual Keyword and Metadata Overhaul
**When:** January 2027
**Effort:** 8-10 hours
**Impact:** High -- prevents staleness

- [ ] Complete keyword research from scratch
- [ ] Rewrite description entirely (fresh perspective)
- [ ] New screenshot designs
- [ ] New app preview video
- [ ] Set goals for year 2

---

## Measurement Framework

### Monthly Scorecard

| Metric | Month 1 | Month 2 | Month 3 | Month 6 | Month 12 |
|--------|---------|---------|---------|---------|----------|
| Total Downloads | | | | | |
| Monthly Downloads | | | | | |
| Average Rating | | | | | |
| Total Ratings | | | | | |
| Conversion Rate | | | | | |
| Keywords in Top 10 | | | | | |
| Keywords in Top 50 | | | | | |
| Revenue | | | | | |

### Success Benchmarks (Year 1)

| Timeframe | Downloads | Rating | Keywords Top 10 |
|-----------|-----------|--------|----------------|
| Month 1 | 200+ | 4.5+ | 1-2 |
| Month 3 | 1,000+ cumulative | 4.5+ | 3-5 |
| Month 6 | 3,000+ cumulative | 4.5+ | 5-8 |
| Month 12 | 10,000+ cumulative | 4.5+ | 8-12 |

These targets assume organic growth only (no paid acquisition). Paid campaigns, press coverage, or App Store featuring would accelerate significantly.

---

## Decision Tree: When to Iterate

```
Downloads declining?
  YES -> Check conversion rate
    Conversion declining? -> Update screenshots/icon (visual problem)
    Conversion stable? -> Check impressions
      Impressions declining? -> Update keywords (visibility problem)
      Impressions stable? -> External factor (seasonal, competitor)
  NO -> Continue current strategy, focus on growth levers

Rating declining?
  YES -> Analyze recent reviews
    Bug reports? -> Fix bugs, submit update
    Feature complaints? -> Prioritize roadmap item
    UX confusion? -> Improve onboarding/UI
  NO -> Continue, maintain review response cadence

No reviews coming in?
  YES -> Implement/adjust SKStoreReviewController prompt
  NO -> Continue
```

---

**The single most impactful ASO activity for a new app is responding to every review within 24 hours and iterating on keywords monthly for the first 6 months.** Everything else is optimization on top of those two fundamentals.
