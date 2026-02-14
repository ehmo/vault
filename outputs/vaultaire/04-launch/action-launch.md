# Launch Execution Tasks -- Vaultaire

**Purpose:** Consolidated action checklist for launch day and the first 72 hours.

---

## Pre-Launch Final Checks (March 4, 2026 -- Day Before)

### Go/No-Go Criteria
- [ ] App status in ASC: "Pending Developer Release" (approved)
- [ ] Landing page at vaultaire.app loads correctly
- [ ] Privacy policy at vaultaire.app/privacy loads correctly
- [ ] Support email receives test message
- [ ] AASA file serves correctly (test universal link: vaultaire.app/s)
- [ ] No unresolved P0 crashes in Sentry from TestFlight

### Prepare Launch Assets
- [ ] Social media posts drafted and ready to publish:
  - Twitter/X post (280 chars, include App Store link)
  - Reddit posts for r/privacy, r/ios, r/security (follow sub rules)
  - Hacker News Show HN post
  - Product Hunt listing (if prepared)
- [ ] Email to beta testers drafted
- [ ] Any press contacts notified with embargo lift date

---

## Launch Day Execution (March 5, 2026)

### T-0: Release (9:00 AM)
- [ ] Log in to App Store Connect
- [ ] Navigate to the approved version
- [ ] Click "Release This Version"
- [ ] Note the exact release time for records
- [ ] Verify status changes to "Ready for Distribution"

### T+15m: Verify (9:15 AM)
- [ ] Open App Store on a device -- search for "Vaultaire"
- [ ] Try the direct App Store link: https://apps.apple.com/app/vaultaire/id6740526623
- [ ] If app not yet visible in search, this is normal -- can take 1-24 hours
- [ ] Direct link should work within minutes

### T+1h: Update Web (10:00 AM)
- [ ] Update vaultaire.app landing page App Store link (if placeholder existed)
- [ ] Verify the link works from the landing page
- [ ] Confirm universal link handler at /s still works

### T+1.5h: Announce (10:30 AM)
- [ ] Publish social media posts (in order of likely impact):
  1. Personal network / Twitter/X
  2. Reddit r/privacy (most aligned audience)
  3. Reddit r/ios
  4. Hacker News -- "Show HN: Vaultaire -- encrypted photo vault with Secure Enclave, duress vault, no account needed"
  5. Product Hunt (if listing created)
- [ ] Send email to beta testers

### T+2h: First Check (11:00 AM)
- [ ] Check Sentry for any crash reports from real users
- [ ] Check App Store Connect analytics:
  - App Units (downloads)
  - Impressions
  - Product Page Views
- [ ] If crashes: assess severity, begin fix immediately

### T+3h: Monitor (12:00 PM)
- [ ] Check for first reviews in App Store Connect
- [ ] Check social media for engagement / questions
- [ ] Respond to any community discussions

### T+6h: Afternoon Review (3:00 PM)
- [ ] Comprehensive metric check:
  - Downloads so far
  - Impressions by source (search, browse, external)
  - Any reviews?
  - Crash-free rate in Sentry
- [ ] Respond to all reviews posted today
- [ ] Engage with social media / Reddit / HN comments

### T+12h: End of Day (9:00 PM)
- [ ] Final daily metrics snapshot:
  - Total downloads day 1
  - Total impressions
  - Conversion rate (downloads / product page views)
  - Number of reviews and average rating
  - Crash count
- [ ] Document any issues to address in v1.1
- [ ] Plan tomorrow's monitoring schedule

---

## Day 2 (March 6, 2026)

### Morning
- [ ] Check overnight downloads and reviews
- [ ] Respond to any new reviews (within 24 hours of posting)
- [ ] Check if app appears in keyword searches now (may have taken overnight to index)
- [ ] Record keyword rankings for top 10 target keywords:
  - "photo vault"
  - "private photos"
  - "encrypted photos"
  - "secret album"
  - "hide photos"
  - "lock photos"
  - "secure folder"
  - "photo locker"
  - "privacy vault"
  - "pattern lock"

### Afternoon
- [ ] Follow up on HN/Reddit posts if still active
- [ ] Analyze day 1 vs day 2 download trend
- [ ] If crashes reported: triage and begin fixing

---

## Day 3 (March 7, 2026)

### Morning
- [ ] Review responses for all outstanding reviews
- [ ] 72-hour metric summary:
  - Total downloads (3 days)
  - Daily average
  - Rating (average and count)
  - Conversion rate trend
  - Keyword visibility

### Assessment
- [ ] Is download trend increasing, stable, or declining?
- [ ] Is conversion rate above 5%? (good for utilities category)
- [ ] Any negative review patterns? (same bug reported multiple times?)
- [ ] Are screenshots performing? (high impression-to-product-page-view ratio?)
- [ ] Decision: submit v1.1 update or wait for more data?

---

## First Week Summary Template

Create this document on March 12 (one week post-launch):

```
## Vaultaire Launch -- Week 1 Summary

### Downloads
- Day 1: ___
- Day 2: ___
- Day 3: ___
- Day 4: ___
- Day 5: ___
- Day 6: ___
- Day 7: ___
- Total: ___
- Daily average: ___

### Conversion Funnel
- Impressions: ___
- Product Page Views: ___
- Downloads: ___
- Impression > Page View rate: ___%
- Page View > Download rate: ___%
- Overall conversion rate: ___%

### Reviews
- Total reviews: ___
- Average rating: ___
- 5-star: ___
- 4-star: ___
- 3-star: ___
- 2-star: ___
- 1-star: ___
- All reviews responded to: YES/NO

### Keyword Rankings
| Keyword | Day 1 Position | Day 7 Position | Change |
|---------|---------------|---------------|--------|
| photo vault | | | |
| private photos | | | |
| encrypted photos | | | |
| ... | | | |

### Issues
- Critical bugs: ___
- Feature requests: ___
- Negative patterns: ___

### Decisions for Week 2
- [ ] Metadata changes needed?
- [ ] Screenshot changes needed?
- [ ] v1.1 update scope?
- [ ] Additional marketing push?
```

---

## Key Metrics Targets (First Month)

| Metric | Minimum | Good | Excellent |
|--------|---------|------|-----------|
| Week 1 downloads | 50 | 200 | 500+ |
| Conversion rate | 3% | 5% | 8%+ |
| Average rating | 4.0 | 4.5 | 4.8+ |
| Keyword in top 100 | 3 | 5 | 10+ |
| Keyword in top 10 | 0 | 1 | 3+ |
| Crash-free rate | 98% | 99% | 99.5%+ |

Note: These targets are for a new, non-promoted app in a competitive category. Organic downloads without paid acquisition will be modest initially. The goal for month 1 is establishing a quality baseline and iterating on metadata.
