# Visual Assets Specification - Vaultaire: Encrypted Vault

**Platform:** Apple App Store
**Last Updated:** 2026-02-12

---

## App Icon Requirements

### Technical Specifications

| Requirement | Specification |
|-------------|---------------|
| Size | 1024x1024 pixels |
| Format | PNG |
| Color Space | sRGB or Display P3 |
| Alpha Channel | NO (not allowed for App Store) |
| Layers | Flattened (single layer) |
| Safe Zone | 820x820px (avoid critical elements in outer 102px border) |

### Design Recommendations

**Visual Display Size:**
- Home Screen: 60x60px (actual size users see)
- Search Results: 40x40px
- App Store Listing: 120x120px

**Design Strategy for "Encrypted Vault" App:**

1. **Icon must be recognizable at 60x60px** - Keep design simple and bold
2. **Instant category recognition** - Users should immediately understand it's a security/vault app
3. **Trust and security visual language** - Use established security metaphors

**Concept Options:**

### Option A: Lock + Shield (Security Focus)
- Central padlock icon
- Shield outline background
- Color: Deep blue (#1A237E) + electric cyan (#00E5FF) accent
- Style: Modern, flat, minimal gradient
- Conveys: Protection, security, trust

### Option B: Vault Door (Direct Metaphor)
- Circular vault door with spokes
- Subtle 3D depth
- Color: Dark grey (#263238) + gold accent (#FFD700)
- Style: Slightly skeuomorphic (recognizable metaphor)
- Conveys: Secure storage, bank-level security

### Option C: Geometric Lock (Modern Minimalist)
- Abstract geometric lock shape
- Clean lines, modern aesthetic
- Color: Gradient purple (#6A1B9A) to cyan (#00BCD4)
- Style: Ultra-flat, contemporary
- Conveys: Modern security, tech-forward

**Color Psychology for Security Apps:**
- Blue: Trust, reliability (most common for security)
- Purple: Privacy, exclusivity
- Black/Grey: Sophistication, seriousness
- Avoid: Red (danger), yellow (warning), green (go/open)

**A/B Testing Priority: HIGH**
Icon testing typically yields 20-30% CVR improvement. Plan to test 2-3 icon variants.

### Icon Testing Strategy

Test these concepts with real users before finalizing:

1. **User Testing (Pre-Launch)**
   - Show 3 icon concepts to 50+ target users
   - Ask: "What does this app do?" (category recognition test)
   - Ask: "Would you trust this app with private photos?" (trust test)
   - Measure: Recognition rate, trust score

2. **App Store A/B Testing (Post-Launch)**
   - Use Apple's Product Page Optimization tool
   - Test winning concept vs 1-2 alternatives
   - Measure: Install conversion rate
   - Duration: Minimum 14 days per test

**Design Resources:**
- Xcode includes App Icon template with size guides
- SF Symbols (Apple's icon library) for consistent iOS design language
- Consider lock.shield.fill or lock.rectangle.fill as starting points

---

## Screenshots Requirements

### Technical Specifications

**iPhone 6.7" Display (REQUIRED)**
- Size: 1290x2796 pixels
- Format: PNG or JPEG
- Orientation: Portrait (can include 1-2 landscape if app supports)
- Quantity: 3-10 screenshots (recommend 5-7)

**iPhone 6.5" Display (REQUIRED)**
- Size: 1284x2778 pixels

**iPhone 5.5" Display (OPTIONAL but recommended for older devices)**
- Size: 1242x2208 pixels

**iPad Pro 12.9" (if iPad supported)**
- Size: 2048x2732 pixels
- iPad-specific screenshots required if app is universal

### Screenshot Strategy

**Critical Fact:** First 2-3 screenshots determine 80% of install decisions. Most users never scroll past the third screenshot.

**Screenshot Order (Priority):**

### Screenshot 1: Hero Feature + Key Benefit
**Content:** Main vault view with encrypted photos grid
**Text Overlay:** "Military-Grade Encryption for Your Private Photos"
**Visual Elements:**
- Show grid of blurred/obscured photo thumbnails (privacy-respectful)
- Lock icon overlays on thumbnails
- Clean, organized interface
- Text: 36-40pt bold, white text with dark shadow or overlay bar

**Goal:** Immediate understanding of app purpose + trust signal

### Screenshot 2: Unique Differentiator (Duress Vault)
**Content:** Side-by-side comparison - real vault vs duress vault
**Text Overlay:** "Duress Vault: Show a Fake Vault Under Pressure"
**Visual Elements:**
- Split screen showing two different vault interfaces
- Arrow or vs graphic between them
- Subtitle: "Your real photos stay hidden"

**Goal:** Highlight unique feature competitors don't have

### Screenshot 3: Security Credibility
**Content:** Security features showcase
**Text Overlay:** "Secure Enclave Hardware Encryption"
**Visual Elements:**
- Lock screen with pattern unlock
- Security badge/shield icons
- List of security features with checkmarks:
  - ✓ AES-256-GCM Encryption
  - ✓ Secure Enclave Keys
  - ✓ No Cloud Storage Required
  - ✓ Open Source Encryption

**Goal:** Build trust with technical audience

### Screenshot 4: Import & Organization
**Content:** Import flow and organization features
**Text Overlay:** "Import from Camera, Photos, or Files"
**Visual Elements:**
- Show import sheet with multiple source options
- Grid and list view toggle
- Search bar
- Organized folders/albums

**Goal:** Show ease of use and organization capabilities

### Screenshot 5: iCloud Backup & Sharing
**Content:** Backup and sharing features
**Text Overlay:** "Encrypted Backup & Secure Sharing"
**Visual Elements:**
- iCloud backup settings screen
- Share sheet for vault sharing
- Encryption indicators
- "Everything stays encrypted" callout

**Goal:** Address backup concerns and show collaboration features

### Screenshot 6-7 (Optional): Additional Features
- Recovery phrase backup screen
- Settings/customization options
- File type support (photos, videos, documents)

### Design Guidelines for Screenshots

**Text Overlays:**
- Font Size: 36-48pt for headlines, 24-30pt for body
- Font: San Francisco (iOS system font) or similar sans-serif
- Color: White text with 50% black overlay bar or strong drop shadow
- Contrast: WCAG AAA compliant (4.5:1 minimum)
- Position: Top or bottom third of screen (avoid middle - covers UI)

**UI Presentation:**
- Show actual app UI (not mockups)
- Use realistic but privacy-respecting content (no real personal photos)
- Consistent device frame (use Screenshot Studio or similar)
- Status bar: Show full signal, Wi-Fi, battery (looks polished)

**Visual Hierarchy:**
- Feature benefit (text) should be readable in 1 second
- App UI should look clean and professional
- Use white space effectively
- Avoid cluttered screens

**Tools:**
- Xcode Simulator for capturing screenshots
- Screenshot Studio / Previewed / AppLaunchpad for device frames and overlays
- Figma/Sketch for text overlay design

---

## App Preview Video (Optional but Recommended)

### Technical Specifications

| Requirement | Specification |
|-------------|---------------|
| Length | 15-30 seconds (recommended 20-25s) |
| Resolution | 1080x1920 (portrait) or 1920x1080 (landscape) |
| Format | M4V, MP4, or MOV |
| Frame Rate | 30 fps |
| File Size | Max 500 MB |
| Audio | Optional (video auto-plays on mute; consider subtitles) |

### Video Strategy

**Purpose:** Show app in action - demonstrate workflow not possible in static screenshots.

**Recommended Script (20 seconds):**

1. **0-3s:** App icon animation → open app → pattern unlock
2. **3-8s:** Import photo from camera → file encrypts with animation
3. **8-13s:** Browse encrypted vault grid → tap photo → instant decrypt/view
4. **13-17s:** Show duress vault switch (unique feature)
5. **17-20s:** End card: "Vaultaire: True Encrypted Privacy" + Download CTA

**Production Tips:**
- Record in iPhone simulator at 2x speed, slow down to 1x in post
- Use screen recording (Cmd+R in Simulator)
- Add subtle motion graphics for encryption/security effects
- No audio needed (most users watch on mute)
- If adding audio: Use royalty-free music + voiceover
- Include burned-in subtitles if using voiceover
- Professional tools: ScreenFlow, Camtasia, or After Effects

**A/B Testing:**
Video preview typically improves CVR by 10-15%. Test with/without video after launch.

---

## Implementation Checklist

### Phase 1: Icon Design (Week 1)
- [ ] Design 3 icon concepts (Lock+Shield, Vault Door, Geometric Lock)
- [ ] Test with 50+ target users (category recognition + trust)
- [ ] Finalize winning concept
- [ ] Export at 1024x1024px, PNG, no alpha channel
- [ ] Validate in Xcode asset catalog
- [ ] Submit to App Store Connect

### Phase 2: Screenshots (Week 1-2)
- [ ] Capture base screenshots from app on 6.7" simulator
- [ ] Design text overlay templates (consistent style)
- [ ] Create 5 core screenshots (hero, duress, security, import, backup)
- [ ] Add device frames and text overlays
- [ ] Export at correct resolutions for all device sizes
- [ ] Upload to App Store Connect
- [ ] Preview on real devices

### Phase 3: App Preview Video (Week 2, Optional)
- [ ] Write 20-second script
- [ ] Record screen capture in simulator
- [ ] Edit with motion graphics and text overlays
- [ ] Add music/voiceover if desired
- [ ] Export at 1080x1920, 30fps, M4V format
- [ ] Upload to App Store Connect
- [ ] Test auto-play behavior

### Phase 4: A/B Testing Setup (Post-Launch)
- [ ] Monitor baseline CVR for 2 weeks with launch assets
- [ ] Design alternative icon concepts
- [ ] Set up Product Page Optimization test in App Store Connect
- [ ] Run icon A/B test for 14 days (33% control, 33% variant A, 33% variant B)
- [ ] Analyze results and implement winner
- [ ] Test screenshot order variations (move duress vault to position 1)

---

## Visual Asset Testing Priority

| Asset | CVR Impact | Testing Effort | Priority | Recommendation |
|-------|-----------|----------------|----------|----------------|
| App Icon | 20-30% | Medium | **HIGHEST** | Test 3 variants post-launch |
| Screenshot 1 | 10-20% | Low | **HIGH** | Test headline variations |
| Screenshot 2 | 5-10% | Low | **MEDIUM** | Test duress vault as #1 vs #2 |
| Video Preview | 10-15% | High | **MEDIUM** | Launch without, add after 2 weeks |
| Screenshots 3-5 | 2-5% | Low | **LOW** | Optimize after other tests complete |

**Testing Sequence:**
1. Launch with best-guess assets (based on user research)
2. Week 3-4: A/B test app icon (biggest impact)
3. Week 5-6: Test screenshot 1 headline
4. Week 7-8: Test screenshot order (duress vault position)
5. Week 9+: Add video preview if CVR needs boost

---

## Design Resources

**Tools:**
- SF Symbols App (Apple's icon library)
- Xcode Asset Catalog (icon management)
- Figma/Sketch (design and mockups)
- Screenshot Studio / Previewed (screenshot mockups with device frames)
- ScreenFlow / Camtasia (video screen recording)

**Reference:**
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/
- App Store Product Page: https://developer.apple.com/app-store/product-page/
- Screenshot Best Practices: https://developer.apple.com/app-store/product-page/#screenshots

**Inspiration:**
- Search "photo vault" on App Store and analyze top 10 apps
- Note: Most competitors use lock/shield icons (consider differentiation)
- Competitors: Private Photo Vault, KeepSafe, LockMyPix (study their screenshots)

---

## Quality Checklist

Before uploading to App Store Connect:

**Icon:**
- [ ] 1024x1024px, PNG, no alpha channel
- [ ] Recognizable at 60x60px on actual device
- [ ] Conveys "security" or "vault" immediately
- [ ] Different enough from competitors
- [ ] No text (too small to read at display size)

**Screenshots:**
- [ ] Correct resolution for all required device sizes
- [ ] Text overlays are readable on all devices
- [ ] No personal information visible
- [ ] UI looks polished and professional
- [ ] First 3 screenshots tell complete story
- [ ] Text contrast meets WCAG AAA standard
- [ ] Device frames consistent across all screenshots

**Video (if included):**
- [ ] 15-30 seconds length
- [ ] Shows actual app UI (not marketing animation)
- [ ] Demonstrates core workflow
- [ ] Subtitles included if voiceover used
- [ ] Tests well on mute (most common viewing mode)
- [ ] File size under 500 MB

---

**Next Steps:**
1. Review this spec with design team
2. Create initial icon concepts
3. Test concepts with target users
4. Produce screenshots from app
5. Upload to App Store Connect
6. Monitor CVR and iterate
