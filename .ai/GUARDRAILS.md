# Vaultaire UI/UX Immutable Guardrails

**CRITICAL: These principles are NON-NEGOTIABLE. Violating them will break user experience and require immediate rollback.**

## 1. Pattern Board Positioning (HIGHEST PRIORITY)

### The Rule
**Pattern boards must NEVER move. They stay perfectly centered on screen with error messages appearing BELOW, never overlapping.**

### Implementation
- Use equal `Spacer()` above and below the pattern board
- Error/feedback area must have **fixed height** (typically 80pt) positioned below the board
- Add explicit spacing between board and error (e.g., 40pt) to push error lower
- Never use `ZStack` or absolute positioning that could cause overlap
- Never put the board at "top" of a VStack - it must be centered

### Example (CORRECT)
```swift
VStack(spacing: 0) {
    Spacer()  // Equal top space
    
    patternInputSection  // Board stays CENTERED
    
    Spacer().frame(height: 40)  // Push error lower
    
    Group {  // Error area
        if showError { ErrorView() }
        else { Color.clear }
    }
    .frame(height: 80)  // FIXED height
    
    Spacer()  // Equal bottom space
}
```

### Anti-Patterns (NEVER DO)
- ❌ Moving board to "avoid" error messages
- ❌ Using `ZStack` where error could overlap board
- ❌ Variable height error areas that push board up/down
- ❌ Board positioned at top of screen

---

## 2. Layout Stability (NO JUMPS)

### The Rule
**Layout shifts are unacceptable. When UI state changes (errors appear, buttons show loading), nothing else moves.**

### Implementation
- Use **fixed heights** for all dynamic content areas (errors, loading states, validation feedback)
- Use `Color.clear` as placeholder when content is hidden
- Never use conditional rendering that changes container sizes
- Use `.opacity()` instead of `if/else` for showing/hiding elements when size matters

### Examples (CORRECT)
```swift
// Fixed height error area
Group {
    if let error = errorMessage {
        ErrorView(error)
    } else {
        Color.clear  // Maintains height
    }
}
.frame(height: 80)  // Never changes

// Opacity for toolbar (no layout shift)
toolbarContent
    .opacity(showingSettings ? 0 : 1)
    .allowsHitTesting(!showingSettings)
```

### Anti-Patterns (NEVER DO)
- ❌ Conditional rendering: `if showError { ErrorView() }`
- ❌ Variable heights based on content
- ❌ Adding/removing views that affect spacing
- ❌ Flexible spacers in critical positioning

---

## 3. Text Wrapping (NEVER TRUNCATE)

### The Rule  
**Text must NEVER truncate. All descriptive text must wrap to multiple lines on smaller screens.**

### Implementation
- Always add `.lineLimit(nil)` to subtitle/description text
- Always add `.multilineTextAlignment(.center)` for centered text
- Always add `.fixedSize(horizontal: false, vertical: true)` for proper sizing
- Test on iPhone SE / smallest display

### Examples (CORRECT)
```swift
Text("Vaultaire works best with these permissions. You can change them anytime in Settings.")
    .font(.subheadline)
    .foregroundStyle(.vaultSecondaryText)
    .multilineTextAlignment(.center)
    .lineLimit(nil)  // CRITICAL: Allows wrapping
    .padding(.horizontal, 24)
```

### Anti-Patterns (NEVER DO)
- ❌ Text that cuts off with "..." on small screens
- ❌ Missing `.lineLimit(nil)` on multi-line text
- ❌ Assuming text will fit on one line

---

## 4. Button Positioning

### The Rule
**Primary action buttons stay at bottom of screen. Content above adjusts but button remains anchored.**

### Implementation
- Use `VStack` with `Spacer()` to push button to bottom
- Pin button with consistent bottom padding (24-40pt)
- Content area scrolls if needed, button stays visible

### Examples (CORRECT)
```swift
VStack(spacing: 0) {
    // Content
    ScrollView { ... }
    
    Spacer()  // Push button down
    
    Button("Continue") { ... }
        .padding(.bottom, 24)  // Anchored at bottom
}
```

---

## 5. Safe Area & Layout Guides

### The Rule
**Respect safe areas but prevent unwanted layout shifts from safe area changes.**

### Implementation
- Use `.ignoresSafeArea(.container, edges: .top)` for content that should stay fixed when toolbar changes
- Never let safe area changes affect centered content
- Test with/without keyboard, with/without navigation bars

### Examples (CORRECT)
```swift
// Empty state that doesn't jump when toolbar appears
emptyStateContent
    .ignoresSafeArea(.container, edges: .top)
```

---

## 6. Spacing & Visual Hierarchy

### The Rule
**Consistent spacing creates visual rhythm. Group related items, separate unrelated ones.**

### Implementation
- Use consistent spacing values (8, 12, 16, 20, 24, 32, 40)
- Related items: 8-12pt spacing
- Section breaks: 20-32pt spacing  
- Major sections: 40pt+ spacing
- Percentage-based spacing for responsive layouts (`h * 0.04`)

---

## 7. Testing Requirements

### The Rule
**All UI changes must be tested on smallest display (iPhone SE) to verify no truncation or layout issues.**

### Checklist
- [ ] Test on iPhone SE simulator/device
- [ ] Verify no text truncation
- [ ] Verify pattern board stays centered
- [ ] Verify no layout jumps when errors appear
- [ ] Verify buttons accessible at bottom
- [ ] Test with dynamic type (accessibility sizes)

---

## 8. Recovery When Rules Broken

### If You Break Pattern Board Centering
1. **STOP immediately**
2. Revert to last known good commit
3. Analyze what moved the board (usually conditional rendering or variable heights)
4. Fix using equal spacers + fixed error area approach
5. Test thoroughly before committing

### If You Break Text Layout
1. Add `.lineLimit(nil)` immediately
2. Test on small display
3. Verify wrapping works correctly

---

## Summary: The Three Sacred Rules

1. **PATTERN BOARD NEVER MOVES** - Centered with equal spacers, fixed error area below
2. **NO LAYOUT SHIFTS** - Fixed heights, `Color.clear` placeholders, `.opacity()` over conditional
3. **TEXT NEVER TRUNCATES** - Always `.lineLimit(nil)` on descriptive text

**Violating any of these will require immediate rollback and is considered a P0 bug.**