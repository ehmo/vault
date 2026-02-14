# Encryption Export Compliance -- Vaultaire

## Classification

| Field | Value |
|-------|-------|
| **ECCN** | 5D992.c |
| **Description** | Mass market encryption software |
| **Encryption** | AES-256-GCM (256-bit symmetric) |
| **Framework** | Apple CryptoKit + Security (Secure Enclave) |
| **License Exception** | ENC under EAR 740.17(b)(1) |
| **Authorization Type** | MMKT (Mass Market) |

## Why 5D992.c?

Vaultaire uses AES-256-GCM encryption via Apple's CryptoKit to encrypt user files at rest. This is:
- **Standard cryptography** (AES is a NIST/IETF standard, not proprietary)
- **Mass market** (available to general public on App Store)
- **Not custom** (uses Apple's built-in CryptoKit framework)

This classifies under ECCN 5D992.c: "Mass market" encryption software meeting the criteria of the Cryptography Note (Note 3 to Category 5, Part 2).

---

## Step 1: App Store Connect (Before Submission)

### Info.plist (Already Done)
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
```

### Questionnaire Answers (On Upload)

When uploading a build, App Store Connect asks:

1. **Does your app use encryption?** → **YES**
2. **Does your app qualify for any of the exemptions?** → **YES** (mass market, standard algorithms)
3. **Does your app implement proprietary or non-standard encryption?** → **NO**
4. **Is your app a mass market product?** → **YES**

After answering, Apple provides an export compliance code. Add it to Info.plist:
```xml
<key>ITSEncryptionExportComplianceCode</key>
<string>[CODE FROM APPLE]</string>
```

This skips the questionnaire on future uploads.

---

## Step 2: BIS Annual Self-Classification Report

### What It Is

A CSV file emailed to BIS and NSA listing your encrypted product. Required for mass market software self-classified under ECCN 5D992.c that's exported (distributed internationally via App Store).

### When to File

| Calendar Year | Due Date | Status |
|--------------|----------|--------|
| 2025 | Feb 1, 2026 | N/A (app not distributed in 2025) |
| **2026** | **Feb 1, 2027** | **File this one** (first year of distribution) |
| 2027+ | Feb 1 of next year | Only if product changes; otherwise email "no changes" |

### The CSV File

Pre-filled at: `outputs/vaultaire/04-launch/bis-self-classification.csv`

Contents:
```
PRODUCT NAME: Vaultaire: Encrypted Vault
MODEL NUMBER: 1.0
MANUFACTURER: Wraxle LLC
ECCN: 5D992.c
AUTHORIZATION TYPE: MMKT
ITEM TYPE: Mobility and mobile applications n.e.s.
SUBMITTER: Wraxle LLC
PHONE: +1 (406) 233-9897
EMAIL: support@vaultaire.app
ADDRESS: 3525 Del Mar Heights Rd Unit 818 San Diego CA 92130
NON-U.S. COMPONENTS: N/A
NON-U.S. MANUFACTURING: N/A
```

### How to File

**Email the CSV to both:**
1. `crypt@bis.doc.gov`
2. `enc@nsa.gov`

**Subject line:** `Annual Self-Classification Report - Wraxle LLC - 2026`

**Body:**
```
Please find attached the annual self-classification report for
Wraxle LLC for calendar year 2026, per EAR 740.17(b)(1).

Product: Vaultaire: Encrypted Vault
ECCN: 5D992.c
Authorization: MMKT (Mass Market)
Encryption: AES-256-GCM via Apple CryptoKit framework

Regards,
Wraxle LLC
```

**Attach:** `bis-self-classification.csv`

### Subsequent Years

If nothing changes (same product, same encryption), you can either:
- Resubmit the same CSV, or
- Send an email stating "No changes since previous report"

Each product only needs to appear in the report **once** (the year it was first self-classified).

---

## Step 3: App Store Connect Encryption Declaration

In App Store Connect under **App Information > Export Compliance**:

1. Select "Yes" for "Does your app use encryption?"
2. Select "Yes" for "Does your app qualify for any of the exemptions?"
3. Specify: uses standard AES-256-GCM via Apple CryptoKit
4. No CCATS number needed (self-classification is sufficient)

---

## Key Dates Calendar

| Date | Action |
|------|--------|
| Before submission | Answer ASC encryption questionnaire |
| Before submission | Add compliance code to Info.plist |
| **Feb 1, 2027** | **File BIS self-classification for 2026** |
| Feb 1, 2028+ | File again or confirm "no changes" |

---

## References

- [Apple: Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
- [Apple: Export Compliance Documentation](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)
- [BIS: Annual Self-Classification](https://www.bis.gov/learn-support/encryption-controls/annual-self-classification)
- [BIS: Encryption Controls](https://www.bis.doc.gov/index.php/policy-guidance/encryption)
- [EAR Section 740.17](https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17) (License Exception ENC)
