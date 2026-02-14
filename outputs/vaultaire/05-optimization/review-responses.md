# Review Response Templates -- Vaultaire

**Response Time Goal:** Under 24 hours for all reviews
**Tone:** Professional, knowledgeable about security, empathetic, concise
**Platform:** Apple App Store only

---

## Guidelines for All Responses

1. Address the reviewer by name if visible (Apple shows developer name, not user name -- but reference "your" experience)
2. Keep responses under 5-6 sentences -- App Store review responses have character limits
3. Never be defensive about security claims -- explain calmly with technical accuracy
4. Never reveal implementation details that could aid attackers
5. Always provide a way to contact support for complex issues
6. Reference specific features or upcoming fixes rather than vague promises
7. Do NOT use emojis in review responses

---

## Positive Reviews (5 Stars)

### Template P1: General Praise
```
Thank you for the review. We are glad Vaultaire is working well for
protecting your private files. If you have suggestions for future features,
we would love to hear them at [support email]. Your feedback helps us
improve.

-- The Vaultaire Team
```

### Template P2: Security/Encryption Appreciation
```
Thank you -- security is at the core of everything we build. AES-256-GCM
with Secure Enclave hardware keys means your data stays protected even if
the device is compromised. We appreciate you trusting Vaultaire with your
privacy.

-- The Vaultaire Team
```

### Template P3: Specific Feature Mention (Duress Vault)
```
Thank you for highlighting the duress vault feature. We built it because
we believe privacy tools should protect people in high-pressure situations,
not just everyday use. We are continuing to strengthen these protections
in upcoming updates.

-- The Vaultaire Team
```

### Template P4: Specific Feature Mention (No Account Required)
```
We are glad the no-account design resonates with you. We intentionally
built Vaultaire so that even we have zero access to your data -- no email,
no server-side accounts, no way for us to see what you store. Privacy
should not require trust.

-- The Vaultaire Team
```

### Template P5: Switching From Competitor
```
Welcome to Vaultaire. We designed the app specifically for users who want
genuine encryption rather than just a PIN screen. Your files are encrypted
at rest with AES-256-GCM, and your key is protected by the Secure Enclave.
Thank you for making the switch.

-- The Vaultaire Team
```

---

## Negative Reviews (1-2 Stars)

### Template N1: Bug Report / Crash
```
We are sorry you experienced a crash. This is not acceptable and we are
investigating. Could you email us at [support email] with your iOS version
and a description of what you were doing when it happened? We want to fix
this as quickly as possible.

Update: [If fix is submitted, add: "Version X.Y includes a fix for this
issue. Please update and let us know if it resolves the problem."]

-- The Vaultaire Team
```

### Template N2: Forgot Pattern / Locked Out
```
We understand how frustrating it is to be locked out. For security reasons,
Vaultaire cannot bypass your pattern -- this is by design, because if we
could bypass it, so could an attacker.

If you set up a recovery phrase during onboarding, you can use it to regain
access. Go to the lock screen and look for the "Recover" option.

If you did not save your recovery phrase, unfortunately your data cannot
be recovered. We know this is painful, and in our next update we are adding
more prominent reminders to save the recovery phrase.

-- The Vaultaire Team
```

### Template N3: Feature Missing / Limitation
```
Thank you for the feedback. We hear you on [requested feature] and it is
on our development roadmap. We are a small team and prioritize based on
user demand, so your input directly influences what we build next.

In the meantime, [suggest workaround if one exists]. Please feel free to
share more details at [support email].

-- The Vaultaire Team
```

### Template N4: UI/UX Complaint
```
We appreciate the honest feedback about the interface. We are continuously
refining the design to make Vaultaire easier to use without compromising
security. Your specific suggestions are valuable -- could you share more
detail at [support email]? We read every message.

-- The Vaultaire Team
```

### Template N5: Subscription/Pricing Complaint
```
Thank you for the feedback on pricing. We understand budget matters.

The free version of Vaultaire includes [list free features: encrypted
storage, pattern lock, in-app camera, up to 100 files]. Premium features
like [iCloud backup, shared vaults, unlimited storage] are priced to
sustain ongoing development and security updates.

Encryption software requires continuous maintenance to stay ahead of
threats, and subscription revenue allows us to keep investing in your
security. We hope you will give the free tier a try.

-- The Vaultaire Team
```

### Template N6: Performance / Slow
```
We are sorry about the performance issues. Large vaults with many high-
resolution photos can be demanding. A few things that may help:

1. Ensure you are on the latest version of the app
2. Restart the app if it has been open for a long time
3. If importing many files, the initial encryption takes time but only
   happens once

If the issue persists, please email [support email] with details about
how many files are in your vault and your device model. We will investigate.

-- The Vaultaire Team
```

---

## Neutral Reviews (3 Stars)

### Template M1: "Good But Needs Work"
```
Thank you for the balanced review. We agree that [acknowledged issue] needs
improvement and it is actively being worked on for our next update.

What you described about [positive aspect] is exactly what we aim for. We
want to bring that same quality to every part of the app. Stay tuned for
updates, and feel free to share additional feedback at [support email].

-- The Vaultaire Team
```

### Template M2: "Works But Nothing Special"
```
Thank you for trying Vaultaire. While the interface may look similar to
other vault apps, what sets Vaultaire apart is under the hood: genuine
AES-256-GCM encryption with Secure Enclave hardware key protection. Most
competing apps use simple PIN locks without real encryption of the files
themselves.

We are working on making these security advantages more visible in the
app experience. Thank you for the feedback.

-- The Vaultaire Team
```

---

## Security/Privacy Concern Reviews

### Template S1: "Is it really encrypted?"
```
Yes, every file stored in Vaultaire is encrypted with AES-256-GCM before
it is written to disk. Your encryption key is derived from your pattern
and protected by the Secure Enclave -- a dedicated hardware security chip
in your iPhone. This means even if someone extracts the raw storage, the
files are unreadable without your pattern.

We use Apple's CryptoKit and Security frameworks for all cryptographic
operations. No homebrew crypto, no shortcuts.

-- The Vaultaire Team
```

### Template S2: "Can you see my photos?"
```
No. Vaultaire is designed so that no one -- including us -- can access
your data. There are no accounts, no server-side keys, and no backdoors.
Your encryption key exists only on your device, protected by the Secure
Enclave hardware. We have zero ability to decrypt your files. That is not
a policy choice -- it is a technical impossibility by design.

-- The Vaultaire Team
```

### Template S3: "What about iCloud backup -- is that safe?"
```
Vaultaire's iCloud backup uses streaming AES-256-GCM encryption. Your
files are encrypted locally on your device BEFORE they are uploaded to
iCloud. The encryption key is derived from your pattern and never leaves
your device. iCloud stores only encrypted blobs that are unreadable
without your device and pattern.

This is different from a standard iCloud backup, which Apple could
theoretically decrypt. Vaultaire's encrypted backup is end-to-end: only
you can read it.

-- The Vaultaire Team
```

### Template S4: "What happens if I lose my phone?"
```
If you saved your recovery phrase (shown during onboarding), you can
restore your vault on a new device using that phrase plus your iCloud
encrypted backup. The recovery phrase is the only way to reconstruct
your encryption key on a new device.

If you did not save your recovery phrase and do not have an iCloud
backup, your data cannot be recovered. This is the security tradeoff:
no backdoors means no recovery path without the phrase.

We strongly recommend writing down your recovery phrase and storing it
in a safe place. A future update will add additional recovery reminders.

-- The Vaultaire Team
```

---

## Feature Request Reviews

### Template F1: Face ID / Touch ID Request
```
Thank you for the suggestion. Biometric unlock is something we are
evaluating carefully. The security tradeoff is complex: biometrics can
be compelled (a court order or someone holding your finger to the
sensor), while a pattern you know cannot be extracted from you in the
same way.

That said, we understand the convenience value and are exploring options
like biometric unlock as an optional convenience layer on top of the
pattern. Stay tuned.

-- The Vaultaire Team
```

### Template F2: Android Version Request
```
We appreciate the interest. Vaultaire is currently iOS-only, which
allows us to leverage Apple-specific hardware security features like
the Secure Enclave. An Android version would require a different
security architecture.

It is on our long-term radar, but we want to get the iOS experience
right first. Thank you for the support.

-- The Vaultaire Team
```

### Template F3: Organizational Features (Folders, Albums, Tags)
```
Great suggestion. Better organization is high on our priority list. We
are working on [folders/albums/tags] for an upcoming release. We want
to make sure the organizational features work well with the encryption
layer, which adds some complexity we want to get right.

Thank you for the feedback -- it helps us prioritize.

-- The Vaultaire Team
```

---

## Competitor Comparison Reviews

### Template C1: "Keepsafe/Private Photo Vault is better"
```
Thank you for the comparison. Keepsafe and Private Photo Vault are
well-established apps and we respect what they have built.

Where Vaultaire differs is in the encryption model. Vaultaire encrypts
every file at rest with AES-256-GCM and stores the key in the Secure
Enclave hardware. Many vault apps use a PIN screen as a gate but do
not actually encrypt the underlying files, meaning the raw data is
accessible if someone knows where to look on the filesystem.

We are a newer app and actively improving. If there is a specific
feature from those apps you would like to see in Vaultaire, please
share at [support email].

-- The Vaultaire Team
```

### Template C2: "Apple Hidden Album does the same thing"
```
Apple's Hidden Album is a great privacy feature, but it has important
differences from Vaultaire:

1. Hidden Album files are visible in iTunes/Finder backups
2. Hidden Album does not use per-file encryption
3. Anyone who unlocks your phone with Face ID can access Hidden Album
4. There is no duress protection or secondary vault

Vaultaire adds a layer of genuine cryptographic security on top of
device-level protection. For users who need more than casual privacy,
that distinction matters.

-- The Vaultaire Team
```

---

## Escalation Scenarios

### Data Loss Report (CRITICAL -- respond within 4 hours)
```
We are very sorry to hear about data loss. This is the most serious type
of issue and we want to help immediately.

Please email [support email] with:
1. Your iOS version
2. What happened before the data disappeared
3. Whether you have an iCloud encrypted backup enabled
4. Whether you have your recovery phrase

We will prioritize investigating this. If your data was backed up to
iCloud, there is a good chance we can help you recover it.

-- The Vaultaire Team
```

### Security Vulnerability Report (CRITICAL -- respond within 4 hours)
```
Thank you for reporting this. We take security reports extremely
seriously. Please email the details to [security email or support email]
so we can investigate privately. Public disclosure of potential
vulnerabilities before a fix is available can put users at risk.

We will investigate immediately and respond within 24 hours.

-- The Vaultaire Team
```

---

## Response Tracking

Maintain a simple log of review responses:

| Date | Rating | Issue Category | Response Sent | Follow-up Needed |
|------|--------|---------------|---------------|-----------------|
| | | | | |

### Patterns to Watch For
- Same bug reported 3+ times -> prioritize fix in next update
- Feature requested 5+ times -> add to roadmap
- Confusion about a feature -> improve onboarding/UI
- Security concern repeated -> add FAQ to website, address in description
