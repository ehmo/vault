# Pre-Launch Checklist -- Vaultaire: Encrypted Vault

**Target Launch Date:** March 5, 2026
**Platform:** Apple App Store (iOS only)
**Current Build:** 15 (TestFlight)
**Status:** [ ] / 48 items complete

---

## Phase 1: App Store Metadata

### Title & Subtitle
- [ ] App name reserved in App Store Connect (app.vaultaire.ios)
- [ ] Title finalized: "Vaultaire: Encrypted Vault" (26/30 chars)
- [ ] Subtitle finalized (XX/30 chars) -- recommend: "Private Photo & Video Lock" (26/30)
- [ ] Promotional text written (XX/170 chars) -- can be updated without new submission
- [ ] All character limits validated

### Keywords (100 characters max)
- [ ] Keyword field populated (primary targets):
  - photo vault, private photos, encrypted photos, secret album, hide photos, lock photos
  - secure folder, photo locker, privacy vault, pattern lock, secret photo
- [ ] No duplicate words between title/subtitle and keyword field
- [ ] No competitor brand names in keywords
- [ ] Commas used as separators (no spaces after commas to maximize character usage)

### Description (4000 characters max)
- [ ] Description written with keywords naturally integrated
- [ ] First 3 lines compelling (visible before "more" tap)
- [ ] Feature list formatted with bullet points or line breaks
- [ ] Differentiators highlighted early: AES-256-GCM, Secure Enclave, no account required
- [ ] Call-to-action near the end
- [ ] No claims that cannot be substantiated (avoid "unbreakable", "unhackable")
- [ ] Subscription terms included if IAP exists

### What's New (Version 1.0)
- [ ] Release notes written for initial launch
- [ ] Keep brief -- first version can simply describe core offering

---

## Phase 2: Visual Assets

### App Icon
- [ ] Icon designed at 1024x1024px (App Store marketing)
- [ ] Icon tested at small sizes (60x60px, 29x29px) for readability
- [ ] Icon does not include text (Apple recommendation)
- [ ] Icon does not use a photograph as background
- [ ] Icon follows Apple Human Interface Guidelines
- [ ] Icon uploaded to App Store Connect

### Screenshots (REQUIRED)
- [ ] 6.7" display screenshots (1290x2796px) -- iPhone 15 Pro Max / 16 Pro Max -- REQUIRED
- [ ] 6.5" display screenshots (1284x2778px) -- iPhone 14 Plus / 13 Pro Max
- [ ] 5.5" display screenshots (1242x2208px) -- iPhone 8 Plus (still required for older device support)
- [ ] Minimum 3 screenshots, target 6-8
- [ ] First screenshot: hero shot showing pattern lock or vault grid
- [ ] Screenshot 2: encryption/security visualization (Secure Enclave callout)
- [ ] Screenshot 3: duress vault feature (unique differentiator)
- [ ] Screenshot 4: encrypted sharing / shared vaults
- [ ] Screenshot 5: iCloud backup with encryption
- [ ] Screenshot 6: recovery phrase / no account required
- [ ] Text overlays readable at 24pt+ font
- [ ] Screenshots show actual app UI (not mockups) per App Review guidelines
- [ ] All screenshots uploaded to App Store Connect

### App Preview Video (Optional, Recommended)
- [ ] 15-30 second video created showing pattern draw, vault browse, share flow
- [ ] Video does not contain misleading content
- [ ] Subtitles added (video autoplays muted)
- [ ] Uploaded to App Store Connect

---

## Phase 3: Technical Requirements

### Build Preparation
- [ ] App binary built for distribution (Release configuration, manual signing)
- [ ] Distribution certificate valid: 6DBP6XL5J5
- [ ] App Store provisioning profiles current for all 3 targets (Vault, LiveActivity, ShareExtension)
- [ ] Build uploaded to App Store Connect via Xcode Organizer or xcodebuild
- [ ] Build processed without errors (check "Activity" tab in ASC)
- [ ] No missing compliance or export compliance warnings

### Testing
- [ ] TestFlight internal testing completed (Build 15+)
- [ ] All 29 Maestro E2E flows passing (current: 29/30, 96.7%)
- [ ] 32 unit tests passing (CryptoEngine, SVDFSerializer, ShareSyncCache, SharedVaultData)
- [ ] Crash reports reviewed in Sentry -- zero unresolved P0 crashes
- [ ] Performance tested on oldest supported device (iPhone models back to iOS 15+)
- [ ] Memory usage acceptable for large vaults (streaming encryption verified)
- [ ] Background upload/download reliability verified

---

## Phase 4: Legal & Compliance

### Privacy
- [ ] Privacy policy published at vaultaire.app/privacy (URL accessible from outside the app)
- [ ] Privacy policy covers: data collection, encryption practices, iCloud usage, CloudKit sharing
- [ ] Privacy policy linked in App Store Connect
- [ ] App Privacy "nutrition label" completed in ASC (Data Types section)
  - Data NOT collected: Vaultaire does not collect user data (no accounts)
  - Data linked to user: None
  - Data used for tracking: None

### Encryption Export Compliance (CRITICAL for vault apps)
- [ ] Export compliance declaration completed in App Store Connect
- [ ] Self-classification report filed with BIS (Bureau of Industry and Security)
  - Vaultaire uses AES-256-GCM (mass market encryption) -- eligible for License Exception ENC
  - ECCN: 5D992.c (mass market encryption software)
  - Annual self-classification report due by February 1 each year to BIS and ENC Encryption Request Coordinator
- [ ] If using App Store Connect's "Does your app use encryption?" question:
  - Answer YES -- app uses AES-256-GCM encryption
  - Confirm app qualifies for encryption exemption OR has proper classification
- [ ] Export compliance documentation saved locally for records

### Age Rating
- [ ] Age rating questionnaire completed in App Store Connect
- [ ] Appropriate rating selected (likely 4+ or 9+ -- no mature content in the app itself)
- [ ] Note: even though users may store sensitive content, the APP does not contain it

### Terms of Service
- [ ] Terms of service published at vaultaire.app/terms (if app has subscriptions/IAP)
- [ ] Support URL provided in App Store Connect

---

## Phase 5: App Review Preparation (HIGH PRIORITY for Vault Apps)

### Review Information
- [ ] App Review contact information provided (name, phone, email)
- [ ] Review notes written explaining the app's purpose and how to test
- [ ] Demo instructions: "Draw any pattern with 6+ dots to create a vault. Import photos from the gallery."
- [ ] Explicitly state: "This app provides encrypted personal storage. It does not hide illegal content."
- [ ] Explain duress vault feature: "A secondary pattern opens a decoy vault for personal safety scenarios."
- [ ] Mention compliance: "Uses AES-256-GCM via Apple CryptoKit framework and Secure Enclave via Apple Security framework."

### Rejection Risk Mitigation
- [ ] Reviewed Guideline 1.1 (Objectionable Content) -- app does not promote hiding illegal material
- [ ] Reviewed Guideline 2.3.1 (Hidden Features) -- all features discoverable and documented
- [ ] Reviewed Guideline 5.1 (Privacy) -- no data collection, transparent encryption
- [ ] Reviewed Guideline 5.2 (Intellectual Property) -- no competitor names, original content
- [ ] Prepared written response for potential "this app could be used to hide content" concern
- [ ] App description focuses on "security" and "privacy" rather than "hiding" or "secret"

---

## Phase 6: Business Setup

### App Store Connect Configuration
- [ ] Pricing configured: Free with IAP / Subscription (or set price)
- [ ] Availability: all territories selected (or specific territories)
- [ ] Tax and banking information completed (for paid apps/IAP)
- [ ] App category: Utilities (primary), Photo & Video (secondary)
- [ ] Copyright: "(c) 2026 [Your Name/Company]"
- [ ] Support URL: vaultaire.app or support email

---

## Phase 7: Marketing & Launch Readiness

### Web Presence
- [ ] Landing page live at vaultaire.app (DONE -- exists)
- [ ] App Store link updated on landing page once app is live
- [ ] Share handler page at vaultaire.app/s working (DONE -- exists)
- [ ] AASA file serving correctly for universal links (DONE -- exists)
- [ ] Privacy policy page accessible from landing page

### Support Infrastructure
- [ ] Support email configured (support@vaultaire.app or equivalent)
- [ ] FAQ or help documentation prepared (common questions: forgot pattern, recovery phrase, how encryption works)
- [ ] Bug report mechanism documented

### Analytics & Monitoring
- [ ] Sentry error tracking active (DONE -- integrated)
- [ ] App Store Connect analytics enabled
- [ ] Keyword ranking tracking set up (manual spreadsheet or tool)
- [ ] Conversion rate baseline plan documented

---

## Final Validation

- [ ] All metadata spell-checked (title, subtitle, description, keywords)
- [ ] All links working (privacy policy, terms, support URL, landing page)
- [ ] Screenshots show actual app UI
- [ ] App follows iOS Human Interface Guidelines
- [ ] App follows App Store Review Guidelines
- [ ] Binary submitted for review

---

**Total Items:** 48
**Completed:** 0
**Remaining:** 48

**Estimated Status:**
- Phase 1 (Metadata): Not yet started -- needs writing
- Phase 2 (Visuals): Not yet started -- needs design work
- Phase 3 (Technical): Mostly complete -- Build 15 on TestFlight, tests passing
- Phase 4 (Legal): Not yet started -- privacy policy needed
- Phase 5 (Review Prep): Not yet started -- critical for vault apps
- Phase 6 (Business): Partially complete -- ASC exists, pricing TBD
- Phase 7 (Marketing): Partially complete -- landing page exists

**Estimated Time to Complete All Items:** 40-60 hours of focused work over 3 weeks
