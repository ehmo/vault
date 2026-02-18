# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Plan: Fix Blank Screen, ITMS-90863, and Implement XCUITests

## Pre-requisites: Fix Two Urgent Bugs First

### Bug 1: Blank Screen on Return from Background (P0)

**Root cause**: `applyAppearanceToAllWindows()` sets `window.rootViewController?.view.backgroundColor = resolvedColor` on EVERY `didBecomeActive` and `didBecomeKey` notification. This paints an opaque UIKit layer over SwiftUI content. Combined with `UIView.performWithoutAnimation` + `CATransaction.setDi...

