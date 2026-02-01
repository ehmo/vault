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
}
