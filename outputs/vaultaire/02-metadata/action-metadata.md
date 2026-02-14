# Metadata Implementation Action Items - Vaultaire

**Status:** Ready to Execute
**Last Updated:** 2026-02-12
**Estimated Time:** 2-3 hours (first-time setup)

---

## Pre-Implementation Checklist

Before starting App Store Connect setup, ensure you have:

- [ ] Apple Developer Account (active, paid membership)
- [ ] Bundle ID registered: `app.vaultaire.ios`
- [ ] App binary ready to upload (or prepared to submit metadata before binary)
- [ ] All metadata files reviewed and approved:
  - `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/apple-metadata.md`
  - `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/visual-assets-spec.md`
- [ ] Screenshots designed and ready (minimum 3 for 6.7" display)
- [ ] App icon designed at 1024x1024px
- [ ] Privacy Policy URL live at https://vaultaire.app/privacy
- [ ] Support email active: support@vaultaire.app

---

## Task 1: App Store Connect - Create App Record

**Estimated Time:** 15 minutes

### Steps:

1. **Log in to App Store Connect**
   - URL: https://appstoreconnect.apple.com
   - Use Apple Developer account credentials

2. **Navigate to Apps Section**
   - Click "My Apps" in top navigation

3. **Create New App**
   - Click "+" icon in top-left
   - Select "New App"

4. **Fill in New App Form:**

| Field | Value |
|-------|-------|
| Platforms | iOS (check box) |
| Name | Vaultaire: Encrypted Vault |
| Primary Language | English (U.S.) |
| Bundle ID | app.vaultaire.ios |
| SKU | vaultaire-ios-2026 (or your internal SKU) |
| User Access | Full Access |

5. **Click "Create"**

**Verification:**
- [ ] App appears in "My Apps" list
- [ ] App status shows "Prepare for Submission"

---

## Task 2: App Information Setup

**Estimated Time:** 10 minutes

### Steps:

1. **Navigate to App Information**
   - In app dashboard, click "App Information" in left sidebar

2. **General Information Section:**

| Field | Value | Notes |
|-------|-------|-------|
| Name | Vaultaire: Encrypted Vault | 26/30 characters |
| Privacy Policy URL | https://vaultaire.app/privacy | Must be live before submission |
| Primary Category | Utilities | Best fit for encrypted storage |
| Secondary Category | Photo & Video | Optional but recommended |

3. **Age Rating**
   - Click "Edit" next to Age Rating
   - Answer questionnaire (likely result: 4+)
   - Important questions:
     - Unrestricted web access? NO
     - User-generated content? NO
     - Location features? NO
     - Medical/treatment info? NO

4. **Save Changes**

**Verification:**
- [ ] Age rating calculated and displayed
- [ ] Privacy Policy URL validated (must return 200 status)
- [ ] Categories saved

---

## Task 3: Pricing and Availability

**Estimated Time:** 5 minutes

### Steps:

1. **Navigate to Pricing and Availability**
   - Click "Pricing and Availability" in left sidebar

2. **Set Pricing:**

| Setting | Value | Notes |
|---------|-------|-------|
| Price | Free | Free download with IAP for Pro features |
| Availability | All territories | Or select specific countries |
| Pre-Order | No | Not available for first release |

3. **App Distribution Methods:**
   - [x] App Store
   - [ ] B2B (custom apps) - Unless needed for enterprise

4. **Save Changes**

**Verification:**
- [ ] Price shows as "Free"
- [ ] All desired territories selected
- [ ] Changes saved successfully

---

## Task 4: Version Information - Metadata Entry

**Estimated Time:** 20 minutes

This is where you paste the copy-paste ready metadata from `apple-metadata.md`.

### Steps:

1. **Navigate to Version Information**
   - Click iOS App → [Version Number] → Prepare for Submission

2. **App Store Information Section:**

Copy metadata from `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/apple-metadata.md`:

| Field | Source | Character Limit |
|-------|--------|-----------------|
| Promotional Text | Section: Promotional Text (169 chars) | 170 |
| Description | Section: Description (3,247 chars) | 4,000 |
| Keywords | Section: Keywords Field - PRIMARY VERSION (99 chars) | 100 |
| Support URL | https://vaultaire.app/support | N/A |
| Marketing URL | https://vaultaire.app (optional) | N/A |

3. **Subtitle Field** (iOS 11+)
   - Copy from Section: Subtitle - PRIMARY VERSION (29 chars)
   - Limit: 30 characters

4. **What's New**
   - Copy from Section: What's New (419 chars)
   - For first release, describes launch features

**CRITICAL VALIDATIONS:**

Before saving, verify:
- [ ] Keywords field has NO spaces after commas
- [ ] Promotional text is exactly 169 characters
- [ ] Subtitle is exactly 29 characters
- [ ] Description is exactly 3,247 characters
- [ ] Keywords is exactly 99 characters
- [ ] All text reads naturally (preview on device)

5. **Save as Draft**

**Verification:**
- [ ] All character counts match specifications
- [ ] Text preview looks correct on App Store preview tool
- [ ] No truncation on smaller devices

---

## Task 5: Screenshots Upload

**Estimated Time:** 20 minutes

### Steps:

1. **In Version Information, scroll to App Previews and Screenshots section**

2. **Upload for 6.7" Display (REQUIRED):**
   - Click "+" under "6.7" Display"
   - Upload screenshots 1-5 (PNG or JPEG, 1290x2796px)
   - Drag to reorder (Screenshot 1 = leftmost position)
   - Screenshots appear in order shown

3. **Upload for 6.5" Display (REQUIRED):**
   - Repeat process with 1284x2778px screenshots

4. **Upload for 5.5" Display (OPTIONAL):**
   - Upload 1242x2208px screenshots if supporting older devices

5. **Verify Screenshot Order:**
   - Screenshot 1: Hero feature (encrypted photos grid)
   - Screenshot 2: Duress vault feature
   - Screenshot 3: Security credibility
   - Screenshot 4: Import/organization
   - Screenshot 5: Backup/sharing

**Verification:**
- [ ] Minimum 3 screenshots uploaded per required device size
- [ ] Screenshots appear in correct order
- [ ] Images not distorted or stretched
- [ ] Preview on App Store looks correct

---

## Task 6: App Icon Upload

**Estimated Time:** 5 minutes

### Steps:

1. **Prepare Icon in Xcode:**
   - Open Xcode project
   - Navigate to Assets.xcassets → AppIcon
   - Drag 1024x1024px PNG into "App Store" slot
   - Verify no alpha channel warning

2. **Build Archive:**
   - In Xcode: Product → Archive
   - Icon automatically included in binary

3. **Verify in App Store Connect:**
   - After uploading build, icon appears automatically
   - No manual upload needed in App Store Connect

**Verification:**
- [ ] Icon appears in Xcode asset catalog
- [ ] No warnings about alpha channel
- [ ] Icon looks correct in all size previews

---

## Task 7: App Review Information

**Estimated Time:** 10 minutes

### Steps:

1. **Navigate to App Review Information section**

2. **Contact Information:**

| Field | Value |
|-------|-------|
| First Name | [Your first name] |
| Last Name | [Your last name] |
| Phone | [Your phone with country code] |
| Email | support@vaultaire.app |

3. **Demo Account (CRITICAL for vault apps):**

Apple reviewers need to test your app. Provide:

| Field | Value | Notes |
|-------|-------|-------|
| Username | reviewer@vaultaire.app | Create a demo account |
| Password | [Secure demo password] | Share in secure notes field |
| Required | YES | Vault apps require demo access |

4. **Notes Section:**

```
DEMO ACCOUNT INSTRUCTIONS:

The app requires pattern lock setup on first launch:
1. Open app
2. Create a pattern lock (suggest: simple L-shape for easy testing)
3. Import sample photos from camera or photo library
4. Test duress vault by creating alternative unlock pattern

IMPORTANT FEATURES TO TEST:
- Pattern unlock (primary security)
- Import photos from library
- Duress vault (alternative pattern shows different vault)
- iCloud backup (optional, can enable in settings)
- Encryption is hardware-backed via Secure Enclave

No internet connection required for core functionality.
All photo encryption happens locally on-device.
```

5. **Attachment (Optional):**
   - If duress vault pattern is complex, attach screenshot showing pattern

**Verification:**
- [ ] Demo account credentials provided
- [ ] Instructions clear and complete
- [ ] Contact information accurate

---

## Task 8: Build Upload (From Xcode)

**Estimated Time:** 15 minutes (+ upload time)

### Steps:

1. **In Xcode:**
   - Ensure build number incremented
   - Product → Archive
   - Wait for archive to complete

2. **In Organizer (opens automatically):**
   - Select archive
   - Click "Distribute App"
   - Select "App Store Connect"
   - Follow prompts:
     - Include bitcode: YES
     - Upload symbols: YES
     - Manage Version and Build: Automatically manage

3. **Wait for Processing:**
   - Upload takes 5-30 minutes depending on size
   - Processing in App Store Connect takes 10-60 minutes
   - You'll receive email when ready

4. **In App Store Connect:**
   - Navigate to Activity tab
   - Wait for build to show "Ready to Submit"
   - Go back to version page
   - In Build section, click "+" and select uploaded build

**Verification:**
- [ ] Build shows "Ready to Submit" status
- [ ] Build linked to version in App Store Connect
- [ ] No processing errors or warnings

---

## Task 9: Final Review & Submit

**Estimated Time:** 10 minutes

### Steps:

1. **Review Checklist:**

All required fields completed:
- [ ] App Information (categories, age rating)
- [ ] Pricing and Availability
- [ ] App Store Information (description, keywords, subtitle)
- [ ] Screenshots (minimum required device sizes)
- [ ] App Icon (via build upload)
- [ ] Build linked to version
- [ ] App Review Information (contact + demo account)
- [ ] Privacy Policy URL live and accessible

2. **Preview on App Store:**
   - Use App Store Connect preview tool
   - Check iPhone SE, iPhone 14 Pro, iPhone 14 Pro Max views
   - Verify text not truncated
   - Verify screenshots look professional

3. **Submit for Review:**
   - Click "Submit for Review" button (top right)
   - Review terms and conditions
   - Confirm submission

4. **Wait for Review:**
   - Typical review time: 24-48 hours
   - Status changes: Waiting for Review → In Review → Pending Developer Release (or Ready for Sale)

**Verification:**
- [ ] Submission successful
- [ ] Status shows "Waiting for Review"
- [ ] Email confirmation received

---

## Task 10: Post-Submission Monitoring

**Estimated Time:** 5 minutes daily during review

### Steps:

1. **Check Status Daily:**
   - Log in to App Store Connect
   - Check for status changes or messages from App Review

2. **Respond Quickly to Rejections:**
   - If rejected, read rejection reason carefully
   - Respond to App Review via Resolution Center
   - Fix issues and resubmit within 24 hours if possible

3. **Release Options:**
   - **Automatic:** App goes live immediately after approval
   - **Manual:** You control release timing (recommended for coordinated launch)

**Common Rejection Reasons for Vault Apps:**
- Demo account doesn't work
- Privacy Policy URL not accessible
- App crashes on reviewer's device
- Missing encryption compliance info (see Task 11)

---

## Task 11: Export Compliance (CRITICAL for Encryption Apps)

**Estimated Time:** 5 minutes

Vaultaire uses encryption, so you MUST answer export compliance questions.

### Steps:

1. **When Prompted (during build upload or app review):**
   - "Does your app use encryption?" → YES
   - "Does your app qualify for exemption?" → YES (if using standard iOS encryption)

2. **Exemption Justification:**

Vaultaire qualifies for exemption under ECCN 5A992 because:
- Uses standard iOS CryptoKit and Secure Enclave
- No proprietary encryption algorithms
- Encryption limited to user data protection (not communication)

3. **Add to Info.plist (Recommended):**

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Or if encryption is used but exempt:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
<key>ITSEncryptionExportComplianceCode</key>
<string>5A992</string>
```

**Verification:**
- [ ] Export compliance questions answered
- [ ] Info.plist updated (prevents future prompts)
- [ ] No issues flagged during submission

---

## Task 12: A/B Testing Setup (Post-Approval)

**Estimated Time:** 15 minutes

Wait until app is approved and live before setting up A/B tests.

### Steps:

1. **Access Product Page Optimization:**
   - In App Store Connect, go to app
   - Click "Product Page Optimization" tab

2. **Create First Test (Icon):**
   - Click "Create Product Page Optimization Test"
   - Test Name: "Icon Variant Test - Launch"
   - Element to Test: App Icon
   - Upload 2 alternative icon designs
   - Traffic allocation: 33% / 33% / 33%
   - Start test

3. **Monitor Results:**
   - Check after 7 days for preliminary data
   - Wait 14 days for statistical significance
   - Minimum 5,000 visitors per variant recommended

See `/Users/nan/Work/ai/vault/outputs/vaultaire/03-testing/ab-test-setup.md` for detailed testing strategy.

**Verification:**
- [ ] Test created successfully
- [ ] Traffic evenly distributed
- [ ] Monitoring dashboard accessible

---

## Timeline Summary

| Task | Time | Dependencies | Status |
|------|------|--------------|--------|
| 1. Create App Record | 15 min | Developer account | ⬜ |
| 2. App Information | 10 min | Task 1 | ⬜ |
| 3. Pricing | 5 min | Task 1 | ⬜ |
| 4. Metadata Entry | 20 min | Metadata files ready | ⬜ |
| 5. Screenshots Upload | 20 min | Screenshots designed | ⬜ |
| 6. App Icon | 5 min | Icon designed | ⬜ |
| 7. App Review Info | 10 min | Demo account created | ⬜ |
| 8. Build Upload | 15 min + upload time | Xcode build ready | ⬜ |
| 9. Submit for Review | 10 min | Tasks 1-8 complete | ⬜ |
| 10. Monitor Review | 5 min/day | Task 9 | ⬜ |
| 11. Export Compliance | 5 min | During submission | ⬜ |
| 12. A/B Testing Setup | 15 min | App approved & live | ⬜ |

**Total Estimated Time:** 2-3 hours (excluding build upload and App Review wait time)

---

## Troubleshooting

### Issue: Keywords Field Exceeds 100 Characters
**Solution:** Remove spaces after commas. Copy EXACTLY from metadata file.

### Issue: Screenshots Upload Fails
**Solution:** Verify exact pixel dimensions (1290x2796 for 6.7"). Re-export from design tool.

### Issue: Privacy Policy URL Not Reachable
**Solution:** Test URL in incognito browser. Ensure HTTPS, no redirects, returns 200 status.

### Issue: Demo Account Rejected
**Solution:** Test demo account yourself first. Ensure pattern unlock works. Add clearer instructions in notes.

### Issue: Build Processing Stuck
**Solution:** Wait 60 minutes. If still stuck, re-upload build with incremented build number.

### Issue: App Rejected for Encryption Compliance
**Solution:** Answer export compliance questions. Add ITSAppUsesNonExemptEncryption to Info.plist.

---

## Success Criteria

Before marking complete, verify:

- [ ] All 11 tasks completed successfully
- [ ] App status shows "Waiting for Review" or approved
- [ ] All metadata matches specifications exactly
- [ ] Screenshots uploaded for all required device sizes
- [ ] Demo account tested and working
- [ ] Privacy Policy URL live and accessible
- [ ] Export compliance handled
- [ ] Support email monitored and ready for user inquiries

---

## Next Steps After Approval

1. Monitor App Store Connect Analytics (impressions, CVR, downloads)
2. Set up A/B testing for icon and screenshots (see Task 12)
3. Respond to user reviews promptly (builds trust)
4. Update promotional text monthly with new features/campaigns
5. Plan first update (collect user feedback for 2-3 weeks first)

---

**Files Referenced:**
- Metadata: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/apple-metadata.md`
- Visual Assets: `/Users/nan/Work/ai/vault/outputs/vaultaire/02-metadata/visual-assets-spec.md`
- A/B Testing: `/Users/nan/Work/ai/vault/outputs/vaultaire/03-testing/ab-test-setup.md`

**Support:**
If you encounter issues not covered in troubleshooting, consult:
- Apple Developer Forums: https://developer.apple.com/forums/
- App Store Connect Help: https://help.apple.com/app-store-connect/
