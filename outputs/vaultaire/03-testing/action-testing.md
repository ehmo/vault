# Testing Action Items - Vaultaire

**Status:** Ready to Execute
**Last Updated:** 2026-02-12

---

## Overview

This document provides actionable tasks for implementing the A/B testing strategy outlined in `ab-test-setup.md`.

Tasks are organized by timeline: Pre-Launch, Launch Week, and Post-Launch testing phases.

---

## Pre-Launch Tasks (Complete Before App Goes Live)

### Task 1: Design Alternative App Icons (HIGH PRIORITY)
**Due:** Before launch
**Time Required:** 3-4 hours
**Owner:** Design team

#### Steps:
1. **Review icon specifications**
   - Read: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/visual-assets-spec.md`
   - Note requirements: 1024x1024px, PNG, no alpha channel

2. **Create 3 icon concepts:**
   - **Control (Current):** [Your existing icon design]
   - **Variant A - Lock + Shield:**
     - Central padlock icon with shield background
     - Colors: Deep blue (#1A237E) + cyan accent (#00E5FF)
     - Style: Modern flat with subtle gradient
   - **Variant B - Vault Door:**
     - Circular vault door with spokes
     - Colors: Dark grey (#263238) + gold accent (#FFD700)
     - Style: Slightly skeuomorphic

3. **Export icons:**
   - File names: `icon-control.png`, `icon-lock-shield.png`, `icon-vault-door.png`
   - Verify: 1024x1024px, PNG format, no alpha channel
   - Save to: `/Users/nan/Work/ai/vault/assets/icons/test-variants/`

4. **User test icons (RECOMMENDED):**
   - Show 3 icons to 20+ target users
   - Ask: "What does this app do?" (category recognition)
   - Ask: "Would you trust this app with private photos?" (trust)
   - Document results

**Success Criteria:**
- [ ] 3 icon variants created and exported
- [ ] All icons meet technical specs (1024x1024, PNG, no alpha)
- [ ] Icons recognizable at 60x60px display size
- [ ] User testing feedback collected (optional but recommended)

---

### Task 2: Create Screenshot Variants for Testing
**Due:** Before launch
**Time Required:** 4-6 hours
**Owner:** Design/Marketing team

#### Screenshot Set 1 (Control - Current):
1. **Screenshot 1 - Hero Feature:**
   - Visual: Grid of encrypted photos
   - Headline: "Military-Grade Encryption for Your Private Photos"

2. **Screenshots 2-5:** Import, Duress Vault, Security, Backup (standard order)

#### Screenshot Set 2 (Treatment A - Duress Focus):
1. **Screenshot 1 - Duress Vault:**
   - Visual: Side-by-side comparison (real vs fake vault)
   - Headline: "Show a Fake Vault Under Pressure"

2. **Screenshots 2-5:** Same as control (only Screenshot 1 differs)

#### Screenshot Set 3 (Treatment B - Hardware Focus):
1. **Screenshot 1 - Hardware Security:**
   - Visual: Grid with Secure Enclave badge
   - Headline: "Hardware-Backed Encryption. Unbreakable Privacy."

2. **Screenshots 2-5:** Same as control

#### Steps:
1. Capture base screenshots from app (1290x2796px for 6.7" display)
2. Design 3 different Screenshot 1 variants with text overlays
3. Keep Screenshots 2-5 identical across all sets
4. Export for all required device sizes (6.7", 6.5", 5.5")
5. Save organized by variant:
   - `/Users/nan/Work/ai/vault/assets/screenshots/control/`
   - `/Users/nan/Work/ai/vault/assets/screenshots/treatment-a/`
   - `/Users/nan/Work/ai/vault/assets/screenshots/treatment-b/`

**Success Criteria:**
- [ ] 3 complete screenshot sets created (5 screenshots each)
- [ ] Only Screenshot 1 differs across sets (isolated variable)
- [ ] All screenshots exported at correct resolutions
- [ ] Text overlays readable and high contrast
- [ ] Device frames consistent across sets

---

### Task 3: Set Up Analytics Access
**Due:** Before launch
**Time Required:** 15 minutes
**Owner:** Developer/Marketing lead

#### Steps:
1. **Verify App Store Connect Access:**
   - Log in to https://appstoreconnect.apple.com
   - Confirm access to "Analytics" tab
   - Ensure role has "View Analytics" permission

2. **Familiarize with Metrics:**
   - Navigate to Analytics → App Store → Engagement
   - Review available metrics:
     - App Store Impressions
     - Product Page Views
     - App Units (Installs)
     - Conversion Rate

3. **Set Up Custom Reports (Optional):**
   - Create saved report for daily monitoring:
     - Metric: Conversion Rate
     - Time period: Last 7 days
     - Comparison: Prior period

4. **Document Baseline:**
   - Plan to track first 2 weeks of data as baseline
   - Create spreadsheet or dashboard for tracking

**Success Criteria:**
- [ ] App Store Connect analytics access verified
- [ ] Team knows how to access CVR data
- [ ] Plan in place to track baseline metrics for 2 weeks

---

### Task 4: Review A/B Testing Documentation
**Due:** Before launch
**Time Required:** 30 minutes
**Owner:** All team members involved in ASO

#### Steps:
1. **Read Testing Strategy:**
   - Review: `/Users/nan/Work/ai/vault/outputs/vaultaire/03-testing/ab-test-setup.md`
   - Understand testing priority order
   - Note testing calendar timeline

2. **Understand Product Page Optimization Tool:**
   - Read Apple's guide: https://developer.apple.com/app-store/product-page-optimization/
   - Watch WWDC session if available
   - Understand how to create tests in App Store Connect

3. **Team Alignment:**
   - Ensure all stakeholders understand:
     - Why we're testing (improve CVR by 20-40%)
     - What we're testing (icon, screenshots, video)
     - Timeline (start Week 3 post-launch)

**Success Criteria:**
- [ ] All team members read ab-test-setup.md
- [ ] Team understands testing priority (icon first)
- [ ] Calendar blocked for testing activities

---

## Launch Week Tasks

### Task 5: Submit App with Control (Baseline) Metadata
**Due:** Launch day
**Time Required:** 2-3 hours (see action-metadata.md)
**Owner:** Developer

#### Steps:
1. **Use PRIMARY versions from metadata files:**
   - App Name: Vaultaire: Encrypted Vault
   - Subtitle: Private Photo & File Locker
   - Keywords: PRIMARY VERSION (99 chars)
   - Screenshots: Control Set

2. **Complete App Store Connect submission:**
   - Follow: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/action-metadata.md`
   - Upload control icon and screenshot set
   - Submit for review

3. **Document launch configuration:**
   - Record exact metadata used
   - Save screenshots of App Store Connect settings
   - Note launch date for baseline tracking

**Success Criteria:**
- [ ] App submitted with PRIMARY/control metadata
- [ ] All metadata matches apple-metadata.md specifications
- [ ] Launch configuration documented

---

### Task 6: Monitor Launch Performance (Week 1-2)
**Due:** Daily during first 2 weeks
**Time Required:** 10 minutes per day
**Owner:** Marketing lead

#### Steps:
1. **Daily Metrics Check:**
   - Log in to App Store Connect
   - Navigate to Analytics → Engagement
   - Record:
     - Impressions
     - Product Page Views
     - Installs
     - Conversion Rate (CVR)

2. **Calculate Weekly Averages:**
   - End of Week 1: Average CVR for baseline
   - End of Week 2: Confirm baseline CVR is stable

3. **Determine Test Readiness:**
   - Check if impressions >10,000/week (minimum for testing)
   - Check if installs >500/week (minimum for meaningful CVR data)
   - If traffic too low, consider Search Ads to boost visibility

**Success Criteria:**
- [ ] 2 weeks of baseline data collected
- [ ] Average CVR calculated (likely 15-20% for utilities)
- [ ] Decision made: Proceed with testing or wait for more traffic

---

## Post-Launch Testing Tasks

### Task 7: Icon A/B Test (Week 3-4 Post-Launch)
**Due:** Week 3-4 after launch
**Time Required:** 2 hours setup + 5 min/day monitoring
**Owner:** Marketing lead

#### Steps:

**Setup (Week 3, Day 1):**

1. **Access Product Page Optimization:**
   - App Store Connect → Vaultaire → Product Page Optimization tab

2. **Create Test:**
   - Click "Create Product Page Optimization Test"
   - Test Name: "Icon Variant Test - Launch"
   - Localization: English (U.S.)
   - Element: App Icon

3. **Configure Treatments:**
   - Treatment A: Upload `icon-lock-shield.png`
   - Treatment B: Upload `icon-vault-door.png`
   - Control: Automatically uses current icon

4. **Set Traffic:**
   - Control: 33%
   - Treatment A: 33%
   - Treatment B: 33%

5. **Launch Test:**
   - Click "Start Test"
   - Note start date in testing log

**Daily Monitoring (5 minutes/day):**

1. Check test dashboard for:
   - Impressions per variant (need 5,000+ each)
   - CVR per variant
   - Confidence level indicator

2. Watch for early trends (but don't act until 95% confidence)

**Analysis (Week 4, End of Test):**

1. **After 14 days or 95% confidence:**
   - Review results in App Store Connect
   - Identify winning variant (highest CVR with 95%+ confidence)
   - Document results in test log

2. **Implement Winner:**
   - If Treatment A or B wins:
     - Update icon in Xcode project
     - Submit app update with new icon
     - Stop test and apply winning variant
   - If control wins:
     - Keep current icon
     - Consider designing new concepts for future test

**Success Criteria:**
- [ ] Test created successfully
- [ ] Test runs for minimum 14 days
- [ ] 5,000+ impressions per variant achieved
- [ ] Results documented (winner, CVR improvement, confidence level)
- [ ] Winning variant implemented if significant

---

### Task 8: Screenshot 1 A/B Test (Week 5-6 Post-Launch)
**Due:** Week 5-6 after launch
**Time Required:** 1 hour setup + 5 min/day monitoring
**Owner:** Marketing lead

#### Steps:

**Setup:**

1. **Create Test in App Store Connect:**
   - Product Page Optimization → Create Test
   - Test Name: "Screenshot 1 - Hero Message Test"
   - Element: Screenshots

2. **Upload Screenshot Sets:**
   - Control: Upload 5-screenshot set (current)
   - Treatment A: Upload 5-screenshot set (duress vault focus)
   - Treatment B: Upload 5-screenshot set (hardware focus)

3. **Traffic: 33/33/33**

4. **Launch Test**

**Monitoring & Analysis:**
- Same process as Icon Test (Task 7)
- Run for 14 days
- Implement winning screenshot 1 variant

**Success Criteria:**
- [ ] Test completed successfully
- [ ] Winning screenshot 1 identified
- [ ] Updated screenshots uploaded to App Store Connect

---

### Task 9: Screenshot Order Test (Week 7-8 Post-Launch)
**Due:** Week 7-8 after launch
**Time Required:** 1 hour setup + 5 min/day monitoring
**Owner:** Marketing lead

#### Steps:

**Setup:**

1. **Create 3 Screenshot Sets with Different Order:**
   - Control: Encryption → Duress → Security → Import → Backup
   - Treatment A: Duress → Encryption → Security → Import → Backup
   - Treatment B: Security → Duress → Encryption → Import → Backup

2. **Upload to Product Page Optimization Test**

3. **Run for 14 days**

**Success Criteria:**
- [ ] Optimal screenshot order identified
- [ ] Screenshots reordered if significant improvement found

---

### Task 10: App Preview Video Production & Test (Week 9-10)
**Due:** Week 9-10 after launch
**Time Required:** 6-8 hours production + 1 hour test setup
**Owner:** Marketing/Design team

#### Steps:

**Video Production:**

1. **Script 20-Second Video:**
   - 0-3s: App icon → pattern unlock
   - 3-8s: Import photo → encryption animation
   - 8-13s: Browse vault → decrypt photo
   - 13-17s: Switch to duress vault
   - 17-20s: "Vaultaire: True Encrypted Privacy" end card

2. **Record:**
   - Use iPhone Simulator screen recording (Cmd+R in Xcode Simulator)
   - Capture at 2x speed, slow to 1x in editing
   - Export at 1080x1920 (portrait), 30fps

3. **Edit:**
   - Add text overlays for key actions
   - Add subtle motion graphics for encryption effects
   - Add background music (optional, royalty-free)
   - Include burned-in subtitles if using voiceover

4. **Export:**
   - Format: M4V or MP4
   - Resolution: 1080x1920
   - Frame rate: 30fps
   - Max file size: 500 MB

**A/B Test:**

1. **Create Test:**
   - Product Page Optimization → Create Test
   - Element: App Preview Videos
   - Control: No video (screenshots only)
   - Treatment A: Upload video

2. **Run for 14 days**

3. **Analyze:**
   - Check if video increases CVR by 10%+
   - If yes, keep video permanently
   - If no improvement, remove video

**Success Criteria:**
- [ ] 20-second video produced meeting specs
- [ ] A/B test run comparing video vs no video
- [ ] Decision made based on CVR impact

---

### Task 11: Subtitle Variant Test (Week 11-13, via App Updates)
**Due:** Week 11+ after launch
**Time Required:** 15 minutes per update + 3 weeks monitoring each
**Owner:** Marketing lead

#### Note:
Subtitles cannot be A/B tested via Product Page Optimization. Must use sequential testing via app updates.

#### Steps:

**Phase 1: Baseline (Weeks 1-3, already complete)**
- Subtitle: "Private Photo & File Locker" (PRIMARY)
- Tracked baseline CVR

**Phase 2: Alternative A (Weeks 11-13)**

1. **Submit App Update:**
   - Change subtitle to: "Hide Photos with Encryption" (Alternative A)
   - No other changes (isolate variable)
   - Submit update

2. **Monitor for 3 Weeks:**
   - Track CVR with new subtitle
   - Compare to baseline CVR

3. **Analyze:**
   - If CVR improves 10%+: Keep Alternative A
   - If no improvement: Plan to revert in next update

**Phase 3: Alternative B (Optional, Weeks 14-16)**
- Test: "Secure Vault for Your Photos" (Alternative B)
- Same process

**Success Criteria:**
- [ ] Alternative subtitle tested for 3+ weeks
- [ ] CVR compared to baseline
- [ ] Decision made: Keep winning subtitle or revert to control

---

### Task 12: Keyword Variant Test (Week 11+, via App Updates)
**Due:** Week 11+ after launch
**Time Required:** 15 minutes per update + 4 weeks monitoring
**Owner:** Marketing/ASO lead

#### Steps:

**Phase 1: Baseline (Weeks 1-4, already complete)**
- Keywords: PRIMARY VERSION (99 chars)
- Tracked search impressions by keyword

**Phase 2: Alternative A (Weeks 11-14)**

1. **Submit App Update:**
   - Change keywords to Alternative Version A (100 chars)
   - See: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/apple-metadata.md`

2. **Monitor Search Rankings:**
   - App Store Connect → Analytics → App Store → Sources
   - Check impressions from "App Store Search"
   - Track which keywords driving traffic (use third-party tool if needed)

3. **After 4 Weeks:**
   - Compare search impressions: Alternative A vs PRIMARY
   - Check if more installs from search vs browse

4. **Decision:**
   - Keep keyword set driving most search impressions

**Success Criteria:**
- [ ] Alternative keywords tested for 4+ weeks
- [ ] Search impression data compared
- [ ] Optimal keyword set identified and implemented

---

## Testing Log Template

Use this template to track all test results:

**Location:** `/Users/nan/Work/ai/vault/outputs/vaultaire/03-testing/test-results-log.md`

```markdown
# Test Results Log - Vaultaire

## Baseline Metrics (Launch Week 1-2)
- **Period:** [Start Date] to [End Date]
- **Impressions:** [Total]
- **Product Page Views:** [Total]
- **Installs:** [Total]
- **CVR:** [Percentage]
- **Notes:** [Any observations]

---

## Test 1: Icon Variants
- **Period:** [Start] to [End]
- **Element:** App Icon
- **Results:**
  - Control: [CVR], [Impressions]
  - Treatment A (Lock+Shield): [CVR], [Impressions], [% improvement], [Confidence]
  - Treatment B (Vault Door): [CVR], [Impressions], [% improvement], [Confidence]
- **Winner:** [Control/Treatment A/Treatment B]
- **Improvement:** [+X%]
- **Implemented:** [Yes/No, Date]
- **Learnings:** [Key takeaways]

---

## Test 2: Screenshot 1 Variants
[Same structure as Test 1]

---

[Continue for each test...]
```

---

## Timeline Summary

| Week | Task | Owner | Time |
|------|------|-------|------|
| Pre-Launch | Design icon variants (Task 1) | Design | 3-4h |
| Pre-Launch | Create screenshot variants (Task 2) | Design | 4-6h |
| Pre-Launch | Set up analytics (Task 3) | Dev/Marketing | 15min |
| Pre-Launch | Review docs (Task 4) | Team | 30min |
| Week 0 | Submit app with control metadata (Task 5) | Dev | 2-3h |
| Week 1-2 | Monitor baseline performance (Task 6) | Marketing | 10min/day |
| Week 3-4 | Icon A/B test (Task 7) | Marketing | 2h + 5min/day |
| Week 5-6 | Screenshot 1 A/B test (Task 8) | Marketing | 1h + 5min/day |
| Week 7-8 | Screenshot order test (Task 9) | Marketing | 1h + 5min/day |
| Week 9-10 | Video production & test (Task 10) | Design/Marketing | 8h + 1h |
| Week 11-13 | Subtitle variant test (Task 11) | Marketing | 15min + monitor |
| Week 11-14 | Keyword variant test (Task 12) | Marketing | 15min + monitor |

**Total Time Investment:** ~30 hours over 14 weeks

**Expected CVR Improvement:** 20-40% total (if all tests yield positive results)

---

## Success Criteria & KPIs

### Overall Testing Program Success
- [ ] At least 3 A/B tests completed (icon, screenshot 1, screenshot order)
- [ ] All tests reach 95% statistical confidence
- [ ] Overall CVR improves 20%+ from baseline
- [ ] All test results documented in test log

### Individual Test Success
Each test is successful if:
- [ ] Runs for minimum 14 days (or reaches 95% confidence sooner)
- [ ] 5,000+ impressions per variant
- [ ] Winning variant identified (even if control wins)
- [ ] Results documented and learnings captured

---

## Contingency Plans

### Low Traffic (<10k Impressions/Week)
**Problem:** Not enough traffic to run meaningful A/B tests

**Solutions:**
1. **Run Apple Search Ads campaign** ($100-500/mo to boost traffic)
2. **Wait 4-8 weeks** to accumulate more organic users
3. **Focus on keyword optimization** to increase search impressions
4. **Promote app externally** (social media, Product Hunt, etc.)

### No Statistically Significant Results After 21 Days
**Problem:** Test runs 21 days but no variant reaches 95% confidence

**Solutions:**
1. **Stop test, keep control** (variants likely too similar)
2. **Design more differentiated variants** for future test
3. **Accept lower confidence** (90%) if meaningful business impact

### All Variants Perform Worse Than Control
**Problem:** Both alternatives decrease CVR vs control

**Solutions:**
1. **Keep control** (current assets are already optimized)
2. **Analyze why** variants underperformed (test user assumptions)
3. **Try radically different concepts** in next test

---

## Next Steps

### Immediate (Before Launch)
1. Complete Task 1: Design icon variants
2. Complete Task 2: Create screenshot variants
3. Complete Task 3: Set up analytics access
4. Complete Task 4: Review A/B testing docs

### After Launch
1. Complete Task 6: Monitor baseline for 2 weeks
2. Week 3: Start Task 7 (Icon A/B test)
3. Follow testing calendar through Week 14

### Ongoing
- Update test log after each test completion
- Share results with team
- Continuously iterate based on learnings

---

**Files Referenced:**
- Strategy: `/Users/nan/Work/ai/vault/outputs/vaultaire/03-testing/ab-test-setup.md`
- Metadata: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/apple-metadata.md`
- Visual Assets: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/visual-assets-spec.md`
- Implementation: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/action-metadata.md`
