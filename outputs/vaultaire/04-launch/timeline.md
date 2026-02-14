# Launch Timeline -- Vaultaire: Encrypted Vault

**Target Launch Date:** March 5, 2026 (Thursday)
**Today's Date:** February 12, 2026 (Thursday)
**Time to Launch:** 21 days (3 weeks)
**Platform:** Apple App Store only
**Current State:** Build 15 on TestFlight, 20 dev sessions complete

---

## Why March 5?

- 21 days allows for metadata prep, screenshot creation, compliance filing, and Apple review with buffer
- Avoids weekends for submission (Apple review is slower on weekends)
- Thursday launch aligns with mid-week when App Store editorial is most active
- Build 15 is feature-complete; remaining work is non-code (metadata, visuals, legal, submission)

---

## Week 1: February 12-18, 2026 (Metadata, Legal, Compliance)

### Thursday, February 12
- [ ] Review this launch plan and confirm March 5 target
- [ ] Begin writing App Store description (first draft)
- [ ] Draft subtitle options (30 char limit)
- [ ] Draft keyword field (100 char limit)

### Friday, February 13
- [ ] Finalize App Store description
- [ ] Write promotional text (170 chars, updatable without submission)
- [ ] Write "What's New" notes for v1.0
- [ ] Research keyword opportunities not covered by competitors

### Saturday-Sunday, February 14-15
- [ ] Buffer / catch-up time
- [ ] Draft privacy policy content
- [ ] Draft terms of service content

### Monday, February 16
- [ ] Publish privacy policy at vaultaire.app/privacy
- [ ] Publish terms of service at vaultaire.app/terms
- [ ] Begin encryption export compliance self-classification
  - Determine ECCN (5D992.c for mass market AES-256-GCM)
  - File annual self-classification with BIS if not already done
  - Document compliance for App Store Connect

### Tuesday, February 17
- [ ] Complete App Privacy "nutrition label" in App Store Connect
- [ ] Complete age rating questionnaire
- [ ] Fill in all App Store Connect fields:
  - Support URL
  - Marketing URL (vaultaire.app)
  - Copyright
  - Category (Utilities primary, Photo & Video secondary)
- [ ] Answer encryption export compliance questions in ASC

### Wednesday, February 18
- [ ] Enter all metadata into App Store Connect (draft):
  - Title, subtitle, keywords
  - Description, promotional text
  - What's New
- [ ] Internal review: proofread all text fields
- [ ] Verify no competitor brand names in metadata

---

## Week 2: February 19-25, 2026 (Visual Assets, Final Build, Review Prep)

### Thursday, February 19
- [ ] Design screenshot templates (device frames, text overlay style, color scheme)
- [ ] Plan 6-8 screenshot sequence:
  1. Pattern lock (hero)
  2. Vault grid with encrypted files
  3. AES-256-GCM / Secure Enclave security callout
  4. Duress vault feature
  5. Encrypted sharing via link
  6. iCloud encrypted backup
  7. Recovery phrase (no account needed)
  8. In-app camera (optional)

### Friday, February 20
- [ ] Create all screenshots for 6.7" display (1290x2796px) -- PRIMARY
- [ ] Create all screenshots for 6.5" display (1284x2778px)
- [ ] Add text overlays (clear, readable at small size)
- [ ] Create screenshots for 5.5" display (1242x2208px) if supporting older devices

### Saturday-Sunday, February 21-22
- [ ] Buffer time for screenshot iterations
- [ ] Optional: create 15-30 second app preview video
- [ ] Optional: create promotional images for social media

### Monday, February 23
- [ ] Upload all screenshots to App Store Connect
- [ ] Upload app preview video (if created)
- [ ] Verify icon is uploaded (1024x1024px)
- [ ] Review entire store listing in ASC preview mode

### Tuesday, February 24
- [ ] Prepare final build for submission:
  - Bump build number to 16 (or next after 15)
  - Ensure Release config uses manual signing with distribution cert
  - Run full test suite: unit tests + Maestro flows
  - Fix any remaining warnings
  - Archive and upload via Xcode Organizer
- [ ] Wait for build processing (~1-2 hours)
- [ ] Verify build status is VALID in App Store Connect

### Wednesday, February 25
- [ ] Write App Review notes (CRITICAL):
  - How to test the app (draw pattern, import photos)
  - Explain purpose: personal encrypted storage
  - Explain duress vault: safety feature, not content hiding
  - Mention Apple frameworks used: CryptoKit, Security (Secure Enclave)
  - State encryption compliance: AES-256-GCM, ECCN 5D992.c
- [ ] Prepare for potential rejection scenarios:
  - "App could facilitate hiding content" -- response ready
  - "Missing demo account" -- app requires no account (explain)
  - "Encryption compliance" -- documentation ready
- [ ] Final review of ALL metadata, screenshots, and review notes

---

## Week 3: February 26 - March 4, 2026 (Submission, Review, Pre-Launch)

### Thursday, February 26
- [ ] SUBMIT TO APPLE APP REVIEW
  - Select build in App Store Connect
  - Confirm all metadata fields populated
  - Attach App Review notes
  - Choose release type: "Manually release this version" (recommended for launch coordination)
  - Submit for review
- [ ] Estimated Apple review time: 1-3 business days (up to 5 for encryption apps)
- [ ] Monitor App Store Connect for review status updates

### Friday, February 27
- [ ] Monitor review status
- [ ] If Apple requests information: respond same day
- [ ] Prepare launch announcement draft (social media, email, forum posts)
- [ ] Test landing page links one final time

### Saturday-Sunday, February 28 - March 1
- [ ] Buffer for Apple review (reviews often complete over weekends)
- [ ] If rejected: analyze rejection reason, fix, and resubmit immediately
  - Common vault app rejection reasons and responses documented in submission-guide.md

### Monday, March 2
- [ ] Expected: app approved (or respond to any review feedback)
- [ ] If approved: DO NOT release yet -- wait for launch day
- [ ] Finalize launch announcement content
- [ ] Brief any collaborators / beta testers about launch date

### Tuesday, March 3
- [ ] Verify app is in "Pending Developer Release" state
- [ ] Test all external links (privacy policy, support, landing page)
- [ ] Prepare keyword ranking baseline (search for target keywords, note current positions)
- [ ] Set up daily review monitoring workflow

### Wednesday, March 4 (Day Before Launch)
- [ ] Final go/no-go decision
- [ ] Verify everything is ready:
  - App approved and pending release
  - Landing page updated with correct App Store link
  - Support email working
  - Social media posts scheduled
- [ ] Get a good night's sleep

---

## Launch Day: Thursday, March 5, 2026

### Morning (9:00 AM - 12:00 PM)
- [ ] 9:00 AM -- Release app on App Store Connect ("Release This Version")
- [ ] 9:15 AM -- Verify app appears in App Store search (may take 1-4 hours to propagate)
- [ ] 10:00 AM -- Update landing page at vaultaire.app with live App Store link
- [ ] 10:30 AM -- Post launch announcement:
  - Personal social media
  - Relevant subreddits (r/privacy, r/ios, r/security -- follow each sub's self-promotion rules)
  - Hacker News (Show HN)
  - Product Hunt (if listing prepared)
  - Privacy-focused forums and communities
- [ ] 11:00 AM -- Notify TestFlight beta testers that the app is live
- [ ] 12:00 PM -- Check App Store Connect analytics: first impressions and downloads

### Afternoon (1:00 PM - 6:00 PM)
- [ ] Monitor for crash reports in Sentry
- [ ] Monitor for first reviews
- [ ] Respond to any social media engagement
- [ ] Check keyword search results -- does the app appear?
- [ ] Document baseline metrics:
  - Impressions (search, browse)
  - Product page views
  - Download count
  - Conversion rate

### Evening
- [ ] Respond to any reviews (within 24 hours of posting)
- [ ] Document any issues for first update
- [ ] Celebrate the launch

---

## Post-Launch Week 1: March 6-12, 2026

### Daily Tasks (15 min/day)
- [ ] Check for new reviews -- respond within 24 hours
- [ ] Monitor crash reports in Sentry
- [ ] Track download numbers
- [ ] Check keyword rankings (search App Store for target terms)

### Thursday, March 6 (Launch +1)
- [ ] Analyze first 24 hours:
  - Total downloads
  - Conversion rate (impressions to installs)
  - Any crash spikes?
  - Review sentiment

### Friday, March 7 (Launch +2)
- [ ] Follow up on any community posts from launch day
- [ ] Engage with early reviewers

### Monday, March 9 (Launch +4)
- [ ] First weekly analysis:
  - Downloads trend (growing, flat, declining?)
  - Keyword rankings (any movement?)
  - Conversion rate
  - Top traffic sources
- [ ] Identify any bugs reported by users for first update
- [ ] Begin working on v1.1 update (bug fixes + any quick wins)

### Wednesday, March 11
- [ ] Submit v1.1 update if bug fixes needed
- [ ] Update promotional text based on early feedback (no submission required)

---

## Post-Launch Week 2: March 13-19, 2026

### Monday, March 16
- [ ] Two-week analysis:
  - Total downloads to date
  - Average daily downloads
  - Rating average and count
  - Keyword ranking changes
  - Conversion rate trend
- [ ] Decide if metadata adjustments needed based on data
- [ ] Plan A/B test for screenshots (if conversion rate below 5%)

### Wednesday, March 18
- [ ] Update description or keywords if data shows opportunities
- [ ] Research new keyword opportunities based on actual search data
- [ ] Continue daily review responses

---

## Post-Launch Week 3: March 20-26, 2026

### Monday, March 23
- [ ] Three-week analysis
- [ ] Compare metrics against week 1 and week 2
- [ ] Identify top-performing keywords
- [ ] Identify underperforming keywords to replace
- [ ] Plan next feature update based on user feedback

---

## Post-Launch Week 4: March 27 - April 2, 2026

### Monday, March 30
- [ ] One-month comprehensive review:
  - Total downloads
  - Rating average and total count
  - Keyword rankings for all target terms
  - Conversion rate (target: 5%+)
  - Top feature requests from reviews
  - Revenue (if applicable)
- [ ] Set goals for month 2
- [ ] Plan metadata refresh based on one month of data
- [ ] Begin quarterly keyword research refresh

---

## Milestones Summary

| Date | Milestone | Status |
|------|-----------|--------|
| Feb 12 | Launch plan finalized | Pending |
| Feb 13 | Metadata first drafts complete | Pending |
| Feb 16 | Privacy policy + terms published | Pending |
| Feb 18 | All metadata entered in ASC | Pending |
| Feb 20 | Screenshots created | Pending |
| Feb 24 | Final build uploaded | Pending |
| Feb 25 | Review notes prepared | Pending |
| Feb 26 | **SUBMITTED TO APP REVIEW** | Pending |
| ~Mar 2 | App approved (estimated) | Pending |
| **Mar 5** | **GLOBAL LAUNCH** | Pending |
| Mar 9 | First weekly analysis | Pending |
| Mar 16 | Two-week analysis | Pending |
| Mar 30 | One-month review | Pending |

---

## Contingency Planning

### If Apple review is delayed beyond 5 business days:
- Contact Apple via the Resolution Center or App Review Board
- Buffer built in: submitted Feb 26, launch target Mar 5 = 5 business days
- Can delay launch to Mar 9 (Monday) without major impact

### If app is rejected:
- **Encryption compliance issue**: Provide ECCN documentation, reference Apple CryptoKit usage
- **"Hiding content" concern**: Emphasize personal privacy, encrypted cloud backup, enterprise security use cases. Reference similar approved apps (Keepsafe, Private Photo Vault)
- **Missing information**: Respond same day with requested details
- **Fix and resubmit timeline**: 1-2 days for response, 1-3 days for re-review
- **Worst case**: delays launch by 1 week to ~March 12

### If critical bug found post-launch:
- Prepare and submit emergency update (expedited review available for critical fixes)
- Communicate transparently in review responses
- Update promotional text with "fix coming in next update"

### If conversion rate is below 3%:
- Week 1: Review screenshots -- are first 2 screenshots compelling?
- Week 2: A/B test new screenshots
- Week 3: Revisit subtitle and description copy
- Week 4: Consider icon redesign

---

**Timeline Status:** On track (21 days to launch)
**Confidence Level:** 85% (buffer for review delays, primary risk is rejection for encryption/vault category)
