# Vaultaire Design Guidelines

## Color Palette

All colors defined as asset catalog color sets. Use `Color.vaultXxx` tokens — never hardcode hex/RGB.

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `vaultBackground` | `#D1D1E9` lavender | `#20233C` deep navy | Screen backgrounds, safe area fill |
| `vaultSurface` | `#FFFFFE` near-white | `#323444` slate | Cards, inputs, list rows |
| `vaultText` | `#2B2C34` charcoal | `#E8E8F0` off-white | Headlines, body text |
| `vaultSecondaryText` | `#2B2C34` @ 70% | `#E8E8F0` @ 78% | Captions, labels, timestamps |
| `vaultHighlight` | `#E45858` coral | `#FF6F6F` salmon | Errors, destructive actions, warnings |
| `AccentColor` | `#6246EA` indigo | `#6E5CFA` bright indigo | Buttons, links, interactive elements |

### Color Rules

1. **Never** use `Color.black`, `Color.white`, `Color.gray`, or `.foregroundStyle(.white)` for UI surfaces, text, or controls.
2. **Allowed exceptions** for hardcoded colors:
   - **Camera view**: Black background behind camera preview (standard iOS pattern)
   - **Thumbnail overlays**: White text/icons on semi-transparent dark overlays when content sits on top of user photos/videos (e.g., video duration badges, selection circles)
   - **Accent button text**: White text on `AccentColor` background buttons (for contrast)
   - **Semantic status**: `.green` for success, `.orange` for warnings, `.yellow` for caution — these are semantic, not brand colors
3. **Shadows**: Use default SwiftUI shadows (no color parameter) or very low opacity. Never `Color.black.opacity(...)` for shadow colors.
4. **Overlays/dimming**: Modal overlays should use `Color.primary.opacity(0.3)` or `.ultraThinMaterial`.
5. **Backgrounds**: Every screen root must use `Color.vaultBackground` or `.vaultBackgroundStyle()`.
6. **Input fields**: `TextEditor` and `TextField` backgrounds use `Color.vaultSurface`.

## Typography

System fonts only. No custom typefaces.

| Style | Font | Weight | Usage |
|-------|------|--------|-------|
| Page title | `.title2` | `.bold` | Screen headings |
| Section title | `.headline` | `.semibold` | Section headers, card titles |
| Body | `.body` | `.regular` | Primary content |
| Caption | `.subheadline` | `.regular` | Secondary descriptions |
| Small | `.caption` | `.regular` | Timestamps, fine print |
| Mono | `.caption.monospacedDigit()` | `.regular` | Counters, percentages |

### Typography Rules

1. Use `.foregroundStyle(.vaultSecondaryText)` for secondary text — never `.gray` or `.secondary`.
2. Error text uses `.foregroundStyle(.vaultHighlight)`.
3. Don't combine custom font sizes with semantic styles (e.g., no `.font(.system(size: 14))`).

## Pixel Loader (Mandatory Spec)

One pixel loader. Everywhere. Use the in-app `PixelAnimation.loading` preset as the canonical spec.

### Canonical Configuration

```
Pattern:          [1, 2, 3, 6, 9, 8, 7, 4]  (perimeter walk, clockwise)
Brightness:       3
Shadow brightness: 2
Color:            .accentColor (auto-adapts to dark/light mode)
Timer interval:   0.1s
Animation duration: 0.3s (creates ~3-cell trail via animation overlap)
```

### Factory Methods

| Method | Size | When |
|--------|------|------|
| `PixelAnimation.loading(size: 60)` | 60pt | Default loader |
| `PixelAnimation.loading(size: 80)` | 80pt | Full-screen loading |
| `PixelAnimation.loading(size: 32)` | 32pt | Inline/compact |
| `PixelAnimation.syncing(size: 24)` | 24pt | Badge/indicator (delegates to `loading`) |

### Pixel Loader Rules

1. **Only** use `PixelAnimation.loading(size:)` or `.syncing(size:)` — never instantiate `PixelAnimation` directly.
2. **Never** create alternate patterns, brightness values, or timing.
3. **Never** use `TimelineView` for pixel animations — it resets the view tree and kills the trail effect. Use `Timer.publish` + `.onReceive`.
4. The trail effect comes from `animationDuration (0.3s) > timerInterval (0.1s)`.

## View Modifiers

| Modifier | Usage |
|----------|-------|
| `.vaultBackgroundStyle()` | Full-screen backgrounds |
| `.vaultGlassBackground()` | Card/container backgrounds |
| `.vaultGlassTintedBackground(tint:)` | Colored cards (errors, success states) |
| `.vaultProminentButtonStyle()` | Primary CTA buttons |
| `.vaultSecondaryButtonStyle()` | Secondary/cancel buttons |
| `.vaultBannerBackground()` | Full-width banners |
| `.vaultPatternGridBackground()` | Pattern grid containers |

## Appearance Mode

User-selectable: System, Light, Dark.

### Implementation

1. Stored in `AppState.appearanceMode`, persisted via UserDefaults key `"appAppearanceMode"`.
2. Applied **exclusively** via `UIWindow.overrideUserInterfaceStyle` — affects all windows, sheets, fullScreenCovers, and alerts.
3. **Never** use `.preferredColorScheme()` anywhere — it conflicts with UIKit overrides and fails to revert from explicit (light/dark) back to system mode.
4. New windows (from fullScreenCovers/sheets) are caught via `UIWindow.didBecomeKeyNotification` observer in VaultApp.
5. Settings path: Settings > App Settings > Appearance > System / Light / Dark.

## Layout Patterns

### Form/Settings Screens

```swift
List {
    Section("Header") {
        // Content rows
    }
}
.navigationTitle("Title")
.navigationBarTitleDisplayMode(.inline)
```

### Full-Screen Content (viewers, camera)

```swift
VStack(spacing: 0) {
    // Toolbar
    HStack { ... }
        .padding()
        .background(Color.vaultBackground)

    // Content
    ZStack {
        Color.vaultBackground.ignoresSafeArea()
        // ...
    }
}
```

### Error States

```swift
HStack(spacing: 8) {
    Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(.vaultHighlight)
    Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.vaultHighlight)
}
.padding()
.vaultGlassTintedBackground(tint: Color.vaultHighlight, cornerRadius: 8)
```

### Success States

```swift
Image(systemName: "checkmark.circle.fill")
    .foregroundStyle(.green)
```

## Accessibility

- All interactive elements: `.accessibilityIdentifier("screen_element")`
- Minimum touch targets: 44pt
- Reduce motion: check `@Environment(\.accessibilityReduceMotion)`
- VoiceOver: provide `.accessibilityLabel` and `.accessibilityHint` for non-text controls
