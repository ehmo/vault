# Apple App Store Submission Guide -- Vaultaire

**Purpose:** Step-by-step instructions for submitting Vaultaire to the App Store, with specific guidance for encryption/vault apps that face heightened scrutiny during review.

---

## Part 1: Pre-Submission Setup in App Store Connect

### 1.1 Access App Store Connect

1. Log in at https://appstoreconnect.apple.com
2. Navigate to "My Apps" and select Vaultaire (Bundle ID: app.vaultaire.ios)
3. If the app is not yet created, click "+" > "New App":
   - Platform: iOS
   - Name: Vaultaire: Encrypted Vault
   - Primary Language: English (U.S.)
   - Bundle ID: app.vaultaire.ios
   - SKU: vaultaire-ios-001 (or your preference)

### 1.2 App Information Tab

**Category:**
- Primary: Utilities
- Secondary: Photo & Video

Note: Choosing "Utilities" as primary (rather than "Photo & Video") positions the app as a tool rather than a gallery app. This is strategic because:
- "Utilities" has less competition from mainstream photo apps
- It aligns with the security/privacy positioning
- Competitors like Keepsafe and Private Photo Vault use "Photo & Video" -- differentiating here avoids direct head-to-head in category rankings initially

**Content Rights:**
- Does this app contain, show, or access third-party content? NO
- (The app stores USER content, not third-party content)

**Age Rating:**
- Complete the questionnaire honestly
- Vaultaire does not contain: violence, sexual content, gambling, drugs, etc.
- Expected rating: 4+ (the app itself has no objectionable content)
- Note: Some vault apps get 17+ ratings -- this is typically because they include web browsers or access unrestricted web content. Vaultaire does NOT include a web browser, so 4+ is appropriate.

### 1.3 Pricing and Availability

**Pricing:**
- Set to Free (with IAP) or your chosen price point
- If subscription: configure subscription groups, pricing tiers, and free trial in "Subscriptions" section

**Availability:**
- Select all territories (or specific ones based on your launch strategy)
- Consider starting with English-speaking markets if localization is not ready:
  - United States, United Kingdom, Canada, Australia, New Zealand

---

## Part 2: Preparing the Store Listing

### 2.1 Metadata Entry

Enter all metadata from your approved copy (see prelaunch-checklist.md Phase 1).

**Title** (30 chars max):
```
Vaultaire: Encrypted Vault
```
(26 characters -- leaves 4 chars of headroom)

**Subtitle** (30 chars max):
Recommended options:
```
Private Photo & Video Lock     (26 chars)
Secure Photo & File Storage    (27 chars)
AES-256 Photo & Video Safe     (26 chars)
```

**Keywords** (100 chars max, comma-separated, NO spaces after commas):
```
photo vault,private photos,encrypted photos,secret album,hide photos,lock photos,secure folder,photo locker,privacy,pattern lock
```
(Approximately 100 characters -- prioritize highest-volume terms)

Keyword strategy notes:
- Do NOT repeat words that appear in the title or subtitle (Apple indexes those automatically)
- "vault" is in the title, so exclude it from keywords
- "encrypted" is in the title, so exclude it from keywords
- Singular and plural are treated as the same by Apple's algorithm
- Single-word keywords can combine -- "photo" + "vault" covers "photo vault"

**Promotional Text** (170 chars max):
```
Your photos, encrypted with AES-256-GCM and protected by Secure Enclave hardware keys. No account needed. No one can access your vault -- not even us.
```
(This can be updated at any time without a new app submission -- use it for seasonal messaging or feature announcements.)

### 2.2 Screenshot Upload

Upload screenshots in the following order (the sequence matters for conversion):

| Position | Content | Purpose |
|----------|---------|---------|
| 1 | Pattern lock screen with drawn pattern | Hero: shows core interaction |
| 2 | Vault grid showing encrypted photos/files | Shows what the app does |
| 3 | Security callout: AES-256-GCM + Secure Enclave | Differentiator from competitors |
| 4 | Duress vault demonstration | Unique feature, compelling |
| 5 | Share vault via encrypted link | Social/sharing feature |
| 6 | iCloud encrypted backup | Data safety reassurance |

Upload for each required device size. The 6.7" screenshots are primary and REQUIRED.

### 2.3 App Review Information

This section is CRITICAL for vault/encryption apps. Apple reviewers will scrutinize the app's purpose.

**Contact Information:**
- First Name: [Your name]
- Last Name: [Your name]
- Phone: [Your phone number]
- Email: [Your email]

**Notes for Reviewers:**
```
HOW TO TEST:
1. Launch the app
2. Complete the onboarding: draw a pattern with 6+ connected dots
3. Confirm the pattern
4. You are now in the vault -- tap the + button to import photos from the photo library
5. Files are encrypted with AES-256-GCM using a key derived from your pattern and protected by the Secure Enclave

ABOUT THIS APP:
Vaultaire provides encrypted personal storage for photos, videos, and files.
It uses Apple's CryptoKit framework (AES-256-GCM) and the Secure Enclave
(via the Security framework) for hardware-backed key protection.

This app does NOT contain a web browser, does NOT connect to external servers
for content, and does NOT facilitate sharing of illegal material. All encryption
is performed using Apple's first-party frameworks.

ENCRYPTION COMPLIANCE:
- Algorithm: AES-256-GCM (via Apple CryptoKit)
- Key storage: Secure Enclave (via Apple Security framework)
- Classification: ECCN 5D992.c (mass market encryption)
- The app qualifies for License Exception ENC under U.S. Export Administration
  Regulations as it uses standard encryption for personal data protection.

DURESS VAULT FEATURE:
The "duress vault" is a personal safety feature. If a user is coerced into
opening their vault (e.g., in a dangerous situation), entering an alternate
pattern reveals a separate, empty vault while the real vault remains hidden.
This is a personal safety feature similar to "panic buttons" in home security
systems, designed to protect individuals in threatening situations such as
border crossings, protests, or domestic violence scenarios.

SHARED VAULTS:
Shared vaults use end-to-end encryption via CloudKit. The encryption key is
transmitted via a recovery phrase shared out-of-band (in person or via secure
messaging). Apple/CloudKit infrastructure cannot decrypt the shared content.

NO ACCOUNT REQUIRED:
The app does not require any account creation, email, or sign-in. The user's
pattern IS their authentication. A recovery phrase is generated for backup
purposes. This is a privacy-by-design decision.
```

**Demo Account:**
- Check "Sign-in is not required" -- Vaultaire has no accounts

---

## Part 3: Encryption Export Compliance

### 3.1 Understanding the Requirement

Any app that uses encryption beyond basic HTTPS must declare it. Vaultaire uses AES-256-GCM for file encryption, which is beyond standard TLS/HTTPS.

### 3.2 App Store Connect Encryption Questions

When you submit the build, App Store Connect will ask:

**Q: Does your app use encryption?**
A: **YES**

**Q: Does your app qualify for any of the exemptions provided in Category 5, Part 2 of the U.S. Export Administration Regulations?**
A: **YES** -- Vaultaire qualifies under the **mass market encryption** exemption.

**Explanation:**
- AES-256-GCM is a standard, published encryption algorithm
- The app uses Apple's CryptoKit framework (a publicly available implementation)
- The app is available to the general public (mass market)
- The encryption is used for personal data protection (not government/military use)
- This qualifies for ECCN 5D992.c and License Exception ENC

### 3.3 Annual Self-Classification Report

If you have not already filed, you SHOULD file an annual self-classification report with:
1. **BIS** (Bureau of Industry and Security) at: crypt-supp8@bis.doc.gov
2. **ENC Encryption Request Coordinator** at: enc@nsa.gov

The report should include:
- Product name: Vaultaire: Encrypted Vault
- Manufacturer: [Your name/company]
- ECCN: 5D992.c
- Authorization: License Exception ENC (Section 740.17(b)(1))
- Encryption algorithm: AES-256-GCM
- Key length: 256 bits
- Type: Mobile application for personal data encryption

This report is due by February 1 each year for products first exported in the prior year. Since you are launching in March 2026, your first report would be due February 1, 2027.

### 3.4 Documentation to Keep on File

Save copies of:
- [ ] Self-classification filing (email confirmation)
- [ ] App Store Connect encryption declaration screenshots
- [ ] A brief technical description of your encryption implementation
- [ ] Reference to Apple CryptoKit documentation confirming AES-256-GCM is the algorithm used

---

## Part 4: Building and Uploading

### 4.1 Build Configuration

Vaultaire uses manual signing for Release builds:

```
CODE_SIGN_STYLE = Manual (Release)
CODE_SIGN_IDENTITY[sdk=iphoneos*] = "Apple Distribution"
PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = [Your App Store profile name]
```

All three targets need valid profiles:
1. Vault (main app)
2. VaultLiveActivity (widget extension)
3. ShareExtension

### 4.2 Archive and Upload

**Option A: Xcode Organizer (Recommended for first submission)**
1. Select "Any iOS Device (arm64)" as build target
2. Product > Archive
3. In Organizer, select the archive > "Distribute App"
4. Choose "App Store Connect" > "Upload"
5. Let Xcode handle signing (it will use your manual signing configuration)
6. Wait for upload and processing

**Option B: Command line**
```bash
# Archive
xcodebuild archive \
  -project apps/ios/Vault.xcodeproj \
  -scheme Vault \
  -archivePath /tmp/Vault.xcarchive \
  -destination 'generic/platform=iOS'

# Export for upload
xcodebuild -exportArchive \
  -archivePath /tmp/Vault.xcarchive \
  -exportPath /tmp/VaultExport \
  -exportOptionsPlist apps/ios/ExportOptions.plist
```

Note from Session 20: `xcodebuild -exportArchive` with `destination: upload` requires an App Store Connect API key. For simplicity, use Xcode Organizer for the first submission.

### 4.3 Post-Upload Verification

1. In App Store Connect > Activity, verify the build appears
2. Wait for "Processing" to complete (1-5 minutes)
3. Status should change to "Ready to Submit" or show compliance warnings
4. If compliance warnings appear, address them (usually the encryption declaration)
5. Select this build in the App Store version page

---

## Part 5: Submission

### 5.1 Final Review Checklist

Before clicking "Submit for Review":

- [ ] All required fields populated (no red warnings in ASC)
- [ ] Build selected and status is "Ready to Submit"
- [ ] Screenshots uploaded for all required device sizes
- [ ] App Review notes written (see Part 2.3 above)
- [ ] Encryption declaration completed
- [ ] Privacy policy URL working
- [ ] Support URL working
- [ ] Age rating completed

### 5.2 Release Type Selection

Choose: **"Manually release this version"**

This allows you to control exactly when the app goes live. After Apple approves it, you can release it on your chosen launch day (March 5).

Alternatives:
- "Automatically release" -- goes live as soon as approved (less control)
- "Automatic after date" -- goes live on a specific date after approval

### 5.3 Submit

Click "Submit for Review" and confirm.

The app will move to "Waiting for Review" status. From there:
- "In Review" -- a reviewer is looking at it (typically 24-48 hours to get here)
- "Approved" / "Pending Developer Release" -- ready to go
- "Rejected" -- see Part 6 below

---

## Part 6: Handling Rejection (Vault/Encryption App Specific)

### 6.1 Common Rejection Reasons for Vault Apps

**Rejection: Guideline 1.1 -- "App provides functionality to hide content"**

Response template:
```
Thank you for reviewing Vaultaire. We understand the concern and want to clarify
the app's purpose.

Vaultaire is a personal encrypted storage application, similar to Apple's own
"Hidden" album feature in Photos and the "Protected" folder in Files. It provides
users with AES-256-GCM encryption for their personal photos, videos, and documents.

Key points:
1. We use Apple's own CryptoKit and Secure Enclave frameworks for all encryption
2. The app does not contain a web browser or any content discovery features
3. The app does not facilitate sharing of illegal content
4. Similar apps are currently available on the App Store (Keepsafe, Private Photo
   Vault, Best Secret Folder) serving the same legitimate use case
5. The encryption is for personal data protection, consistent with Apple's own
   privacy-focused design philosophy

We are happy to make any adjustments to the app's description or marketing to
better communicate its legitimate purpose.
```

**Rejection: Guideline 2.3.1 -- "Hidden or undocumented features"**

This could apply to the duress vault feature. Response:
```
The alternate vault (duress vault) feature is fully documented in the app's
settings and is visible to all users. It is not hidden functionality.

This feature serves a critical personal safety purpose: if a user is coerced
into unlocking their device (border crossing, theft, domestic violence), they
can enter an alternate pattern that opens a separate, innocuous vault. This
protects them from physical harm.

Similar "duress" or "decoy" features exist in multiple approved App Store
applications:
- Private Photo Vault (Decoy Password)
- Keepsafe (Decoy Password)

We can add additional in-app documentation or onboarding for this feature
if that would address the concern.
```

**Rejection: Guideline 5.1 -- "Privacy concerns with encryption claims"**

Response:
```
All encryption claims in our App Store listing are accurate and verifiable:

1. "AES-256-GCM" -- implemented via Apple CryptoKit's AES.GCM.seal() API
2. "Secure Enclave" -- implemented via Apple Security framework's
   SecKeyCreateRandomKey with kSecAttrTokenIDSecureEnclave
3. "End-to-end encrypted sharing" -- shared vault keys are derived from
   recovery phrases and never transmitted to our servers. CloudKit stores
   only encrypted blobs.

We do not make claims about being "unbreakable" or "unhackable." Our
description accurately represents the cryptographic primitives used.

We can provide source code excerpts demonstrating the implementation
if that would be helpful for the review.
```

**Rejection: Export compliance issue**

Response:
```
Vaultaire uses AES-256-GCM encryption implemented via Apple's CryptoKit
framework. This qualifies for:

- ECCN: 5D992.c (mass market encryption software)
- License Exception ENC under 15 CFR 740.17(b)(1)

The encryption is:
- A standard, published algorithm (AES-256-GCM, NIST standard)
- Implemented via a publicly available library (Apple CryptoKit)
- Used for personal data protection in a consumer application
- Available to the general public

We have filed/will file the annual self-classification report with BIS
as required. We can provide documentation upon request.
```

### 6.2 Rejection Response Process

1. Read the rejection reason carefully in the Resolution Center
2. DO NOT resubmit immediately -- write a thoughtful response first
3. Use the Resolution Center to reply (not email)
4. Be professional, specific, and reference guidelines by number
5. If you make code changes, describe exactly what changed
6. Resubmit with the response -- aim to respond within 24 hours

### 6.3 Escalation

If you believe the rejection is incorrect after one appeal:
1. Use the App Review Board appeal process in App Store Connect
2. Provide a concise summary of why the rejection does not apply
3. Reference specific guideline language and how your app complies
4. Typical response time: 2-5 business days

---

## Part 7: Post-Approval Release

### 7.1 When Approved

If you chose "Manually release":
1. App status changes to "Pending Developer Release"
2. You can release at any time by clicking "Release This Version"
3. After release, it takes 1-24 hours for the app to appear in search results
4. The app is immediately available via direct link

### 7.2 Release Day Actions

On March 5, 2026 (or your chosen launch day):
1. Click "Release This Version" in App Store Connect at 9:00 AM
2. The direct link will work almost immediately: https://apps.apple.com/app/vaultaire/id[YOUR_APP_ID]
3. Search results may take several hours to index the new app
4. Monitor App Store Connect analytics throughout the day

### 7.3 First Update Planning

Begin planning v1.1 immediately after launch:
- Address any bugs reported in reviews
- Optimize metadata based on first week of search data
- Consider adding features requested in early reviews
- v1.1 review is typically faster than initial review (24-48 hours)
