# A/B Testing Setup - Vaultaire: Encrypted Vault

**Platform:** Apple App Store
**Last Updated:** 2026-02-17

---

## Overview

App Store product page optimization through A/B testing can improve install conversion rates by 20-40%. This document provides step-by-step instructions for setting up and analyzing A/B tests for Vaultaire.

**Testing Tool:** Apple's Product Page Optimization (PPO) feature in App Store Connect

**Testable Elements:**
- App Icon
- Screenshots (up to 3 sets)
- App Preview Videos

**Not Testable via PPO:**
- App Name
- Subtitle
- Keywords
- Description

For untestable elements, you must submit app updates and compare performance over time.

---

## Testing Strategy Overview

### Priority Order (Highest Impact First)

| Test | Est. CVR Impact | Effort | Priority | Timeline |
|------|----------------|--------|----------|----------|
| App Icon | 20-30% | Medium | 🔴 HIGHEST | Week 3-4 post-launch |
| Screenshot 1 (Hero) | 10-20% | Low | 🟠 HIGH | Week 5-6 post-launch |
| Screenshot Order | 5-10% | Low | 🟡 MEDIUM | Week 7-8 post-launch |
| App Preview Video | 10-15% | High | 🟡 MEDIUM | Week 9-10 post-launch |
| Screenshots 2-3 | 2-5% | Low | 🟢 LOW | Week 11+ post-launch |

**General Rule:** Test one variable at a time. Wait for statistical significance before starting next test.

---

## Pre-Test Requirements

Before starting any A/B test:

### Minimum Traffic Thresholds
- **Impressions:** 10,000+ per week (minimum for meaningful test)
- **Installs:** 500+ per week (minimum for conversion tracking)
- **Test Duration:** Minimum 7 days, recommended 14 days
- **Visitors per Variant:** 5,000+ (for 95% statistical confidence)

### App Status
- [ ] App approved and live on App Store
- [ ] At least 2 weeks of baseline data collected
- [ ] Know current conversion rate (CVR) from App Store Connect Analytics

### Design Assets Ready
- [ ] Alternative designs created for test element
- [ ] Assets meet Apple's specifications (resolution, format, file size)
- [ ] Variants are meaningfully different (not minor tweaks)

**If traffic is low (<10k impressions/week):** Wait to accumulate more users before testing. Small sample sizes yield unreliable results.

---

## Test 1: App Icon Variants (HIGHEST PRIORITY)

### Hypothesis
Simplified icon with bold security visual will increase install CVR by 15-25% compared to current icon.

### Why Test Icon First?
- Highest impact on CVR (typically 20-30% improvement possible)
- Icon appears everywhere: search results, Top Charts, Today tab
- First element users see before clicking to product page

---

### Test Configuration

#### Step 1: Design Alternative Icons

Create 2 alternative icon designs based on visual-assets-spec.md recommendations:

**Variant A: Lock + Shield (Security Focus)**
- Design: Central padlock icon with shield outline
- Color: Deep blue (#1A237E) + cyan accent (#00E5FF)
- Style: Modern flat with subtle gradient
- Message: Trust, protection, security

**Variant B: Vault Door (Direct Metaphor)**
- Design: Circular vault door with spokes
- Color: Dark grey (#263238) + gold accent (#FFD700)
- Style: Slightly skeuomorphic
- Message: Bank-level security, secure storage

**Control (Current):** Your existing app icon

**Design Guidelines:**
- Must be 1024x1024px PNG
- No alpha channel
- Test with real users first (category recognition test)
- Ensure recognizable at 60x60px actual display size

---

#### Step 2: Access Product Page Optimization in App Store Connect

1. **Log in to App Store Connect**
   - URL: https://appstoreconnect.apple.com

2. **Navigate to Your App**
   - My Apps → Vaultaire: Encrypted Vault

3. **Open Product Page Optimization**
   - Click "Product Page Optimization" tab in left sidebar
   - If not visible, ensure app is approved and live

4. **Verify Eligibility**
   - App Store Connect shows if your app qualifies for testing
   - Requirements: App live on App Store, not in pre-order

---

#### Step 3: Create Test

1. **Click "Create Product Page Optimization Test"**

2. **Test Setup Form:**

| Field | Value |
|-------|-------|
| Test Name | Icon Test - Security Visuals |
| Localization | English (U.S.) |
| Element to Test | App Icon |
| Treatment A Name | Lock + Shield |
| Treatment B Name | Vault Door |

3. **Upload Assets:**
   - Control: No upload needed (uses current icon)
   - Treatment A: Upload icon-lock-shield.png (1024x1024px)
   - Treatment B: Upload icon-vault-door.png (1024x1024px)

4. **Traffic Allocation:**
   - Control: 33%
   - Treatment A: 33%
   - Treatment B: 33%

**Why 33/33/33?** Even distribution ensures fair comparison. Some teams prefer 50/25/25 (higher control sample), but 33/33/33 reaches significance faster.

---

#### Step 4: Configure Test Settings

1. **Test Duration:**
   - Start Date: [2 weeks after app goes live]
   - End Date: Automatic (when statistical significance reached)
   - Minimum: 7 days
   - Recommended: 14 days

2. **Success Metric:**
   - Primary: Install Conversion Rate (CVR)
   - Apple automatically tracks this

3. **Review & Launch:**
   - Preview how each variant appears on App Store
   - Verify icons look correct in search results and product page
   - Click "Start Test"

---

#### Step 5: Monitor Results

**Where to Check:**
- App Store Connect → Product Page Optimization → [Test Name]

**Metrics Tracked:**
- Impressions per variant
- Product Page Views per variant
- Installs per variant
- Conversion Rate per variant
- **Improvement:** Percentage change vs control

**Dashboard Updates:**
- Real-time (updated every few hours)
- Need 5,000+ visitors per variant for confidence interval

---

#### Step 6: Analyze Results (After 14 Days)

**Statistical Significance Indicators:**

Apple shows confidence level:
- 🔴 Low Confidence: <90% (inconclusive, extend test)
- 🟡 Medium Confidence: 90-94% (promising, but wait)
- 🟢 High Confidence: 95%+ (statistically significant, act on results)

**Example Results Interpretation:**

| Variant | Impressions | Page Views | Installs | CVR | Improvement | Confidence |
|---------|-------------|------------|----------|-----|-------------|------------|
| Control (Current) | 35,000 | 7,000 | 1,050 | 15.0% | - | - |
| Treatment A (Lock+Shield) | 35,200 | 7,800 | 1,404 | 18.0% | +20.0% | 96% ✓ |
| Treatment B (Vault Door) | 34,800 | 6,900 | 1,035 | 15.0% | 0% | - |

**Interpretation:**
- Treatment A wins with 96% confidence (+20% CVR improvement)
- Treatment B performs same as control (no improvement)
- **Action:** Implement Treatment A icon permanently

---

#### Step 7: Implement Winning Variant

1. **If Treatment A or B Wins:**
   - Update app icon in Xcode project (Assets.xcassets → AppIcon)
   - Submit new app version with updated icon
   - In App Store Connect: Stop test → Apply winning variant

2. **If Control Wins:**
   - Keep current icon
   - Stop test
   - Consider testing different icon concepts

3. **If Inconclusive (no 95% confidence after 14 days):**
   - Extend test 7 more days
   - If still inconclusive after 21 days, stop and keep control
   - Possible reason: Variants too similar, not enough traffic

---

#### Step 8: Document Learnings

Record results in testing log:

```markdown
## Icon Test Results (Date: [YYYY-MM-DD])

**Winner:** Treatment A (Lock + Shield icon)
**Improvement:** +20.0% CVR (15.0% → 18.0%)
**Confidence:** 96%
**Traffic:** 35,200 impressions, 1,404 installs over 14 days

**Learnings:**
- Modern flat design with security imagery (lock+shield) outperforms current icon
- Blue color palette performs better than grey/gold
- Security focus resonates with target audience

**Next Steps:**
- Implement Lock + Shield icon in app update
- Test screenshot variants next (Screenshot 1 headline)
```

---

## Test 2: Screenshot 1 (Hero Screenshot)

### Hypothesis
Emphasizing "duress vault" unique feature in Screenshot 1 will increase CVR by 10-15% compared to generic "encrypted photos" message.

### Why Test Screenshot 1?
- First screenshot determines if users scroll further
- 80% of install decisions made from first 1-3 screenshots
- Text overlay headline most impactful variable

---

### Test Configuration

#### Alternative Screenshot 1 Variants

**Control (Current):**
- Visual: Grid of encrypted photos
- Headline: "Military-Grade Encryption for Your Private Photos"

**Treatment A:**
- Visual: Side-by-side duress vault comparison
- Headline: "Show a Fake Vault Under Pressure"

**Treatment B:**
- Visual: Grid with prominent Secure Enclave badge
- Headline: "Hardware-Backed Encryption. Unbreakable Privacy."

---

#### Step-by-Step Test Setup

1. **Create 3 Screenshot Sets:**
   - Each set includes 5-7 screenshots
   - Only Screenshot 1 differs (headline + visual)
   - Screenshots 2-7 remain identical across variants

2. **In App Store Connect:**
   - Product Page Optimization → Create Test
   - Test Name: "Screenshot 1 - Hero Message Test"
   - Element: Screenshots
   - Upload 3 complete screenshot sets

3. **Traffic Allocation:**
   - Control: 33%
   - Treatment A (Duress focus): 33%
   - Treatment B (Hardware focus): 33%

4. **Run for 14 Days**

5. **Analyze:**
   - Check which headline drives highest CVR
   - Look for 95% confidence before implementing

**Expected Outcome:** 8-15% CVR improvement from winning variant

---

## Test 3: Screenshot Order Variation

### Hypothesis
Leading with duress vault feature (currently Screenshot 2) will increase CVR by 5-10% vs leading with generic encryption message.

### Test Configuration

**Control:**
Screenshot Order: Encryption → Duress → Security → Import → Backup

**Treatment A:**
Screenshot Order: Duress → Encryption → Security → Import → Backup

**Treatment B:**
Screenshot Order: Security → Duress → Encryption → Import → Backup

**Setup:** Same as Screenshot 1 test, but reorder screenshots instead of changing content.

**Duration:** 14 days minimum

**Expected Outcome:** 5-10% CVR improvement

---

## Test 4: App Preview Video (Add vs No Video)

### Hypothesis
Adding 20-second app preview video will increase CVR by 10-15% by demonstrating unique duress vault feature in action.

### Test Configuration

**Control:**
- No app preview video (screenshots only)

**Treatment A:**
- 20-second video showing: Pattern unlock → Import photo → Duress vault switch
- Auto-plays on mute
- Placed in first position (before screenshots)

**Production Steps:**
1. **Script Video:**
   - 0-3s: App icon → pattern unlock
   - 3-8s: Import photo → encryption animation
   - 8-13s: Browse vault → decrypt photo
   - 13-17s: Switch to duress vault (unique feature)
   - 17-20s: End card "Vaultaire: True Encrypted Privacy"

2. **Record:**
   - Use iPhone Simulator screen recording
   - Export at 1080x1920 (portrait), 30fps
   - Add text overlays for key actions
   - Include subtle motion graphics for encryption

3. **Upload to App Store Connect:**
   - Product Page Optimization → Create Test
   - Element: App Preview Videos
   - Upload video for Treatment A only

4. **Run Test:** 14 days

**Expected Outcome:** 10-15% CVR improvement (video demonstrates unique feature)

---

## Test 5: Subtitle Variants (Requires App Updates)

### Important Note
Subtitles cannot be A/B tested via Product Page Optimization. You must submit app updates and compare performance periods.

### Test Strategy

**Phase 1: Current (Baseline)**
- Subtitle: "Private Photo & File Locker" (RECOMMENDED VERSION)
- Track baseline CVR for 3 weeks

**Phase 2: Update 1 (After 3 weeks of baseline)**
- Submit app update
- Change subtitle to: "Hide Photos with Encryption" (Alternative A)
- Track CVR for 3 weeks
- Compare to baseline

**Phase 3: Analysis**
- If Alternative A improves CVR by 10%+: Keep it
- If no improvement: Revert to PRIMARY VERSION in next update

**Caution:** Subtitle changes require app submission (7-14 day process including review). Less agile than PPO tests.

---

## Test 6: Keyword Variants (Requires App Updates)

### Important Note
Keywords cannot be A/B tested via Product Page Optimization. Test by submitting updates and monitoring search ranking.

### Test Strategy

**Phase 1: Launch (Weeks 1-4)**
- Keywords: PRIMARY VERSION (see apple-metadata.md)
- Monitor search rankings for target keywords in App Store Connect

**Phase 2: Update 1 (Weeks 5-8)**
- Change keywords to Alternative Version A
- Monitor ranking changes for 4 weeks

**Phase 3: Analysis**
- Compare impressions from search for each keyword set
- Check if more installs come from search vs browse
- Implement keyword set that drives most search impressions

**Tools for Keyword Tracking:**
- App Store Connect Analytics (Impressions by Source)
- Third-party: App Radar, Sensor Tower, Mobile Action

---

## Testing Calendar (First 12 Weeks Post-Launch)

| Week | Activity | Status |
|------|----------|--------|
| 1-2 | Launch. Collect baseline data. | ⬜ |
| 3-4 | Run Icon Test (Treatment A vs B vs Control) | ⬜ |
| 4 | Analyze Icon Test results | ⬜ |
| 5 | Implement winning icon (if significant) | ⬜ |
| 5-6 | Run Screenshot 1 Test (Hero message variants) | ⬜ |
| 6 | Analyze Screenshot 1 results | ⬜ |
| 7 | Implement winning screenshot 1 (if significant) | ⬜ |
| 7-8 | Run Screenshot Order Test | ⬜ |
| 8 | Analyze Screenshot Order results | ⬜ |
| 9 | Produce App Preview Video | ⬜ |
| 9-10 | Run Video Test (video vs no video) | ⬜ |
| 10 | Analyze Video Test results | ⬜ |
| 11 | Implement winning variant, plan next tests | ⬜ |
| 12+ | Test subtitle/keyword variants via app updates | ⬜ |

---

## Success Metrics & KPIs

### Primary Metric
**Install Conversion Rate (CVR):**
- Formula: (Installs / Product Page Views) × 100
- Baseline target: 15-20% (typical for paid utilities)
- Goal after optimization: 25-30%

### Secondary Metrics
- **Impressions:** How many times app appears in search/browse
- **Product Page Views:** How many users click to see full listing
- **Click-Through Rate (CTR):** (Page Views / Impressions) × 100
  - Affected by: Icon, title, subtitle, ratings
- **Retention Day 1:** Percent of installs who open app next day
  - Helps validate that optimization attracts right users (not just more users)

### Success Criteria for Each Test

A test is "successful" if:
1. **Statistical Significance:** 95%+ confidence
2. **Meaningful Impact:** 10%+ improvement in CVR
3. **Sustained Performance:** Winning variant maintains improvement for 2+ weeks after implementation

If test shows <10% improvement even with 95% confidence, consider whether implementation effort is worth small gain.

---

## Tools & Resources

### Apple Official Tools
- **App Store Connect Analytics:** Primary data source (free)
- **Product Page Optimization:** A/B testing tool (free)
- **Search Ads:** Can run ads to increase test traffic (paid)

### Third-Party ASO Tools
- **App Radar:** Keyword tracking, competitor analysis ($50-200/mo)
- **Sensor Tower:** Market intelligence, rankings ($100-500/mo)
- **Mobile Action:** Keyword optimization, creative analysis ($50-300/mo)
- **AppFollow:** Review management, ASO tracking ($50-200/mo)

**Recommendation for Vaultaire:**
- Start with free Apple tools
- Add App Radar after 1 month if serious about ASO (keyword tracking)
- Premium tools optional unless running large marketing budget

---

## Common Pitfalls to Avoid

### 1. Testing Too Many Variables at Once
❌ **Wrong:** Change icon AND screenshot 1 AND subtitle simultaneously
✓ **Right:** Test one element at a time, measure impact

### 2. Stopping Tests Too Early
❌ **Wrong:** See 10% improvement after 3 days, stop test
✓ **Right:** Wait minimum 7 days, preferably 14, for statistical significance

### 3. Small Sample Sizes
❌ **Wrong:** Run test with 500 impressions per variant
✓ **Right:** Wait for 5,000+ impressions per variant (minimum)

### 4. Testing Too Similar Variants
❌ **Wrong:** Test "Encrypted Photos" vs "Photo Encryption" (too similar)
✓ **Right:** Test meaningfully different approaches (e.g., security focus vs duress vault focus)

### 5. Not Documenting Results
❌ **Wrong:** Run test, forget what was learned
✓ **Right:** Document every test result, build knowledge base

### 6. Ignoring Retention
❌ **Wrong:** Optimize only for installs, ignore if users churn next day
✓ **Right:** Check Day 1 retention - ensure optimization attracts right users

---

## A/B Test Tracking Template

Use this template to track all tests:

```markdown
# Test Log - Vaultaire ASO

## Test #1: App Icon Variants
- **Date:** 2026-02-26 to 2026-03-12
- **Element:** App Icon
- **Variants:**
  - Control: [Current icon description]
  - Treatment A: Lock + Shield (blue)
  - Treatment B: Vault Door (grey/gold)
- **Hypothesis:** Security-focused icon will increase CVR 15-25%
- **Traffic Allocation:** 33/33/33
- **Results:**
  - Control: 15.0% CVR, 35,000 impressions
  - Treatment A: 18.0% CVR, 35,200 impressions (+20.0%, 96% confidence) **WINNER**
  - Treatment B: 15.0% CVR, 34,800 impressions (no change)
- **Decision:** Implement Treatment A (Lock + Shield icon)
- **Learnings:** Blue security imagery resonates with privacy-conscious users

## Test #2: Screenshot 1 Hero Message
- **Date:** [Start] to [End]
- **Element:** Screenshot 1 headline
- **Variants:**
  - Control: "Military-Grade Encryption..."
  - Treatment A: "Show a Fake Vault Under Pressure"
  - Treatment B: "Hardware-Backed Encryption..."
- **Hypothesis:** [Your hypothesis]
- **Results:** [To be completed]

[Continue for each test...]
```

---

## Budget & Timeline

### Time Investment
- **Design alternative assets:** 2-4 hours per test
- **Set up test in App Store Connect:** 15 minutes
- **Monitor test:** 5 minutes daily
- **Analyze results:** 30 minutes per test
- **Implement winning variant:** 1-2 hours

**Total over 12 weeks:** ~20-30 hours

### Financial Investment
- **Product Page Optimization:** Free (included with Apple Developer account)
- **Design tools:** Free (Figma, Xcode) or $10-50/mo (paid tools)
- **ASO tracking tools:** $0-200/mo (optional)
- **Search Ads (to boost traffic):** Optional, $100-1000+/mo

**Recommended budget for first 3 months:** $0-500 (mostly free, optional paid tools)

---

## Next Steps

### Immediate (Before Launch)
- [ ] Design 2 alternative app icons for Test 1
- [ ] Create 3 screenshot 1 variants for Test 2
- [ ] Set up App Store Connect analytics access
- [ ] Review A/B testing documentation

### Week 1-2 Post-Launch
- [ ] Collect baseline CVR data
- [ ] Monitor daily impressions and installs
- [ ] Set calendar reminder for Week 3 (start Icon Test)

### Week 3+
- [ ] Launch Icon Test per instructions above
- [ ] Follow testing calendar
- [ ] Document all results in test log

---

**Files Referenced:**
- Metadata: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/apple-metadata.md`
- Visual Assets: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/visual-assets-spec.md`
- Action Items: `/Users/nan/Work/ai/vault/outputs/vaultaire/03-testing/action-testing.md`
