# Vault — Marketing Website Copy

## Hero Section

### Headline
**Your files. Truly hidden.**

### Subheadline
Vault encrypts your private files and makes them invisible — even under pressure. No accounts, no cloud, no trace.

### CTA
Download on the App Store (Free)

---

## The Problem

Every "secure" app on the App Store has the same fatal flaw: they tell the world they're hiding something.

A wrong password shows an error. A locked folder shows a lock icon. A hidden photo app sits right there on your home screen with a name like "Secret Gallery."

If someone forces you to open your phone — a border agent, an abusive partner, a thief — they see the app. They see the lock. They know you're hiding something. And they won't stop until you open it.

**Vault is different. There's nothing to find.**

---

## How It Works

### Draw a pattern. Open a vault.

Draw a pattern on a grid. That pattern unlocks your vault — your photos, videos, documents, all encrypted.

Draw a different pattern? A completely different vault opens. Every pattern is a door to a separate, isolated space.

Enter a wrong pattern? You don't get an error message. You get an empty vault. There is no way to tell the difference between "wrong pattern" and "vault with no files."

No error. No hint. No proof anything exists.

---

## What Makes Vault Different

### Plausible Deniability — Built Into the Architecture

Most vault apps encrypt your files. Vault makes them **undetectable**.

- **Wrong pattern = empty vault, not an error.** Anyone looking over your shoulder sees a working app with nothing in it.
- **All storage looks like random noise.** Vault pre-allocates a 50 MB encrypted block filled with random data. Whether you've stored 0 files or 500, the storage looks identical. Forensic tools cannot determine if data exists at all.
- **No metadata leaks.** No file counts, no thumbnails on the lock screen, no "last opened" timestamps.

### Multiple Hidden Vaults

One app. Unlimited vaults. Each pattern opens a different one.

Keep everyday files in one vault. Private documents in another. Sensitive materials in a third. Each vault is completely invisible to the others. No one — including you — can prove another vault exists without knowing its exact pattern.

### Duress Mode — Protection Under Coercion

Being forced to unlock your phone?

Designate any vault as a **duress trigger**. When that pattern is drawn, all other vaults are silently and permanently destroyed. The duress vault opens normally, showing whatever you've placed there as a decoy.

The person watching sees a cooperating user and an ordinary-looking vault. They have no way to know that anything else ever existed.

### Secure Camera — Capture Without a Trace

Take photos directly into your vault. They never touch your photo library, never appear in "Recently Deleted," never sync to iCloud. The image goes from sensor to encryption with nothing in between.

### One-Time Share Phrases

Need to share a vault with someone you trust?

Vault generates a memorable sentence — not a link, not a QR code. Something like *"the curious fox jumped over seven quiet hills."* Give it to your recipient. They enter the phrase, the vault syncs to their device, and the phrase is permanently burned. It can never be used again.

You control everything after sharing:
- Set expiration dates
- Limit the number of times it can be opened
- Block screenshots
- Revoke access instantly for any individual recipient
- Stop all sharing with one tap

### No Accounts. No Cloud. No Tracking.

Vault has no sign-up screen because there is no account. No email, no phone number, no identity of any kind.

Your files never leave your device unless you explicitly share a vault. There is no analytics, no telemetry, no third-party code. The entire app is built with Apple-native frameworks only — zero external dependencies.

When you do share, all data is encrypted on your device before upload. Apple's CloudKit servers see only encrypted noise.

---

## Security, Not Theater

### Military-Grade Isn't a Marketing Phrase Here

| Layer | What It Does |
|-------|-------------|
| **AES-256-GCM** | The same encryption standard used by intelligence agencies worldwide. Every file, every byte. |
| **PBKDF2 with 600,000+ iterations** | Makes brute-forcing your pattern computationally impractical — even with dedicated hardware. |
| **Secure Enclave binding** | Your encryption keys are bound to your physical device using Apple's tamper-resistant hardware. If someone copies your storage to a computer, the data is useless without your exact device. |
| **Memory zeroing** | Encryption keys are wiped from RAM the instant you lock the app. Nothing lingers. |
| **Timing attack protection** | Every unlock attempt takes a random amount of time, whether right or wrong. Attackers cannot use response timing to narrow down patterns. |
| **Screenshot & screen recording blocking** | The app detects screen capture and locks immediately. Screenshots show a blank screen. |

### What We Don't Do (On Purpose)

**No Face ID / Touch ID.** Biometrics can be compelled — by law enforcement, by court order, by force. A pattern in your head cannot be extracted. Vault deliberately excludes biometric unlock.

**No "Forgot Password" recovery.** There is no server that knows your pattern. There is no email reset. If this concerns you, Vault offers recovery phrases — memorable sentences you write down and keep safe. But there is no backdoor. That's the point.

**No iCloud sync of vault data.** Your encrypted vault can be included in device backups (it remains encrypted), but vault contents never sync across devices through iCloud. Each device is a separate, sovereign copy.

---

## Who Is Vault For?

**Journalists** protecting sources in countries where phone searches are routine.

**Activists** operating under surveillance who need to carry sensitive documentation.

**Domestic abuse survivors** keeping evidence secure on a shared or monitored device.

**Travelers** crossing borders where device searches are mandatory.

**Attorneys** with client-privileged materials on personal devices.

**Anyone** who believes that privacy is not about having something to hide — it's about having something to protect.

---

## Technical Specs

- **Platform:** iOS 17+
- **Price:** Free
- **Size:** Lightweight — no bloat, no ads, no third-party SDKs
- **Storage:** 50 MB pre-allocated encrypted blob per vault (expandable with premium)
- **Encryption:** AES-256-GCM via Apple CryptoKit
- **Key Derivation:** PBKDF2-HMAC-SHA512 (600K–800K iterations)
- **Hardware Security:** Apple Secure Enclave integration
- **Dependencies:** Zero. Built entirely with Apple-native frameworks.
- **Data Collection:** None. No analytics, no telemetry, no tracking.

---

## Final CTA Section

### Your files deserve better than a lock screen.

Other apps hide your files behind a password. Vault makes them disappear.

No accounts. No cloud. No trace. No proof they ever existed.

**Download Vault — Free on the App Store.**

---

*Vault does not collect, transmit, or store any personal information. All encryption is performed locally on your device. We cannot access your files, your patterns, or your recovery phrases — by design.*
