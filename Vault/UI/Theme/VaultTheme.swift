import SwiftUI

// MARK: - Vault Color Palette
//
// Design tokens (light mode):
//   Background:       #d1d1e9  (lavender)
//   Surface / Card:   #fffffe  (near-white)
//   Text / Headline:  #2b2c34  (dark charcoal)
//   Accent / Link:    #6246ea  (indigo-purple)  — set via AccentColor asset
//   Highlight:        #e45858  (coral red)
//   Button text:      #fffffe  (white on accent)
//
// Colors are defined as asset catalog color sets and auto-generated
// by Xcode as Color.vaultBackground, .vaultSurface, .vaultText,
// .vaultSecondaryText, .vaultHighlight.

// MARK: - Convenience View Modifiers

extension View {
    /// Applies the vault background color to the view.
    func vaultBackgroundStyle() -> some View {
        self.background(Color.vaultBackground.ignoresSafeArea())
    }

    /// Glass card background on iOS 26+, solid surface fallback on earlier.
    func vaultGlassBackground(cornerRadius: CGFloat = 12) -> some View {
        Group {
            if #available(iOS 26, *) {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                self.background(Color.vaultSurface)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }

    /// Glass card with tint on iOS 26+, tinted background fallback.
    func vaultGlassTintedBackground(tint: Color, cornerRadius: CGFloat = 12) -> some View {
        Group {
            if #available(iOS 26, *) {
                self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.background(tint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }

    /// Primary CTA: glassProminent on iOS 26+, borderedProminent fallback.
    func vaultProminentButtonStyle() -> some View {
        Group {
            if #available(iOS 26, *) {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.borderedProminent)
            }
        }
    }

    /// Secondary button: glass on iOS 26+, bordered fallback.
    func vaultSecondaryButtonStyle() -> some View {
        Group {
            if #available(iOS 26, *) {
                self.buttonStyle(.glass)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Floating bar material: removes thinMaterial on iOS 26+ (glass buttons provide their own chrome).
    func vaultBarMaterial() -> some View {
        Group {
            if #available(iOS 26, *) {
                self
            } else {
                self.background(.thinMaterial)
            }
        }
    }

    /// Full-width banner: glass on iOS 26+, ultraThinMaterial fallback.
    func vaultBannerBackground() -> some View {
        Group {
            if #available(iOS 26, *) {
                self.glassEffect(.regular, in: .rect(cornerRadius: 0))
            } else {
                self.background(.ultraThinMaterial)
            }
        }
    }

    /// Glass orb for icon circles on iOS 26+, no-op fallback (existing fill remains).
    func vaultGlassOrb() -> some View {
        Group {
            if #available(iOS 26, *) {
                self.glassEffect(.regular.tint(Color.accentColor), in: .circle)
            } else {
                self
            }
        }
    }

    /// Pattern grid background: glass on iOS 26+, translucent surface fallback.
    func vaultPatternGridBackground() -> some View {
        Group {
            if #available(iOS 26, *) {
                self.glassEffect(.regular, in: .rect(cornerRadius: 16))
            } else {
                self.background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.vaultSurface.opacity(0.3))
                )
            }
        }
    }
}
