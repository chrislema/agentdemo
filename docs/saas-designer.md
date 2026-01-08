# UI Guidance
## Frontend Design System & Development Guidelines

This document defines the complete design system and development guidelines for application frontend development.

---

## Navigation System

### Primary Navigation (Feature-Focused)
- **Purpose:** Main workflow features that users access regularly
- **Items:** Primary workflow features (e.g., Home, Dashboard, Reports)
- **Location:** Horizontal menu below the header
- **Alignment:** Right-aligned (unless items take up full row, then left-aligned)
- **Visual:** Active page should be highlighted

### Secondary Navigation (Account/Meta)
- **Purpose:** User account and administrative features
- **Items:** Profile, Team Members, Invites, Plan, Billing, etc.
- **Location:** Vertical dropdown menu
- **Trigger:** User's email address (top right corner with down arrow)
- **Visual:** Small down arrow indicator

---

## Layout Structure

### Header (100px tall)
```
┌──────────────────────────────────────────────────────────────┐
│                    HEADER (100px tall)                       │
│                                                   ┐          │
│  App Name                        user@email.com ▼│15px      │
│  (vertically centered)                           ┘          │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                      [Home | Feature 1 | Feature 2 | Feature 3]  │ ← Primary nav (right-aligned)
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                    Page Content Area                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Header Elements:**
- **App Name:** [Your App Name] - left-aligned, vertically centered in 100px header
- **User Email:** Right-aligned with 15px margin from top
- **Dropdown Arrow:** Small down arrow next to email for secondary navigation

**Primary Navigation:**
- Separate row immediately below header
- Right-aligned by default
- Left-aligned if navigation items would take up the full row
- Active page visually highlighted

---

## Typography

### Font Family Selection

**Requirements:**
- **Source:** Google Web Fonts
- **Style:** Sans Serif fonts only
- **Load from:** Google Fonts CDN

**Approved Font Options:**
Choose one of the following for your application:
- Inter
- Archivo Narrow
- DM Sans
- Space Grotesk
- Libre Franklin
- Source Sans Pro

**Selection Guidance:**
- Use the same font family throughout the entire application
- All fonts provide excellent readability and modern appearance
- Consider the personality/tone that fits your application

### Font Weights
- **Headings/Headers:** 700 or 800 weight (bold or extra bold)
- **Labels:** 400 weight (regular)
- **Button Text:** 400 weight (regular)
- **Body/Page Text:** 400 weight (regular)

**Note:** When loading from Google Fonts, ensure you load both 400 and 700 (or 800) weights.

### Text Colors
**STRICT RULE: Black or White text only. NO grey text.**

- **On White Backgrounds:** Black text (#000000 or derived Contrast color)
- **On Colored Backgrounds:** White text (#FFFFFF)
- **Never use:** Grey text in any shade

---

## Color System

### Core Concept: Tinted Neutrals

**IMPORTANT:** This is a color *system*, not a fixed palette. All colors (except pure white) carry the brand color's hue at varying levels of saturation and lightness. This creates visual harmony throughout the application.

### Color Derivation System

Each color has a specific **role** with derivation rules based on the brand color:

| Role | Derivation Rule |
|------|----------------|
| **brand** | The primary brand color (user-defined) |
| **brand-accent** | Brand hue at ~95% lightness, low saturation (very light, subtle) |
| **brand-alt** | Brand hue at ~80-85% lightness, medium saturation (lighter accent) |
| **brand-alt-accent** | Brand hue at ~40-45% lightness, higher saturation (darker, richer) |
| **contrast** | Brand hue at ~10-15% lightness, very low saturation (almost black with tint) |
| **contrast-accent** | Brand hue at ~85-90% lightness, low saturation (light grey with tint) |
| **base** | Pure white #FFFFFF (no brand tint) |
| **base-accent** | Brand hue at ~45-50% lightness, low saturation (medium grey with tint) |
| **tint** | Brand hue at ~97-99% lightness, very low saturation (almost white with subtle tint) |
| **border-base** | Brand hue at ~93-95% lightness, low saturation (light border with tint) |
| **border-contrast** | Brand hue at ~35-40% lightness, low saturation (darker border with tint) |

### Example Palettes

Here are two complete examples showing how the system works with different brand colors:

#### Example 1: Orange Brand (#F59E0B)
```css
--brand:              #F59E0B;  /* Orange */
--brand-accent:       #FFF5E6;  /* Very light orange */
--brand-alt:          #FFE4B8;  /* Light orange */
--brand-alt-accent:   #6B5A42;  /* Dark orange-brown */
--contrast:           #262418;  /* Almost black with warm tint */
--contrast-accent:    #F0EAE0;  /* Light grey with warm tint */
--base:               #FFFFFF;  /* Pure white */
--base-accent:        #736C5E;  /* Medium grey with warm tint */
--tint:               #FFFCF8;  /* Almost white with subtle orange */
--border-base:        #F2EDE4;  /* Light border with warm tint */
--border-contrast:    #605D56;  /* Darker border with warm tint */
```

#### Example 2: Purple Brand (#5344F4)
```css
--brand:              #5344F4;  /* Purple */
--brand-accent:       #E9E7FF;  /* Very light purple */
--brand-alt:          #DEC9FF;  /* Light purple */
--brand-alt-accent:   #3D386B;  /* Dark purple */
--contrast:           #1E1E26;  /* Almost black with cool tint */
--contrast-accent:    #D4D4EC;  /* Light grey with cool tint */
--base:               #FFFFFF;  /* Pure white */
--base-accent:        #545473;  /* Medium grey with cool tint */
--tint:               #F8F7FC;  /* Almost white with subtle purple */
--border-base:        #E3E3F0;  /* Light border with cool tint */
--border-contrast:    #4E4E60;  /* Darker border with cool tint */
```

### Color Usage Guidelines

**Buttons:**
- Primary buttons: `--brand` background with white text
- Secondary buttons: White background with `--brand` text and border

**Text:**
- Headings: `--contrast` (almost black with brand tint)
- Body text: `--contrast`
- Links: `--brand`

**Backgrounds:**
- Main background: `--base` (white)
- Subtle tint: `--tint`
- Accent sections: `--brand-accent`

**Borders:**
- Light borders: `--border-base`
- Darker borders: `--border-contrast`

**Navigation:**
- Active nav item: `--brand` color or background
- Inactive nav items: `--contrast`

### Design Rules - Colors

**STRICT RULES:**
- ❌ **NO GRADIENTS** - Never use gradients anywhere in the application
- ❌ **NO GREY TEXT** - Only black or white text
- ✅ Solid colors only
- ✅ Use the defined palette consistently

---

## Icons

### Philosophy
Icons are not used for decoration. They should only be included where they provide meaningful context or clarity, typically appearing next to text labels within the application interface.

### Icon Requirements

**Style:**
- **Line icons only** - NO fill/solid icons
- **Single color** - Absolutely NO multi-color icons

**Sizing:**
- Icons must not exceed 120% of the text height next to them
- Keep icons proportional and modest - no large decorative icons

**Colors:**
- **On white backgrounds:** Use `--brand` or `--contrast` color
- **On colored backgrounds:** Use white (e.g., icons inside buttons with `--brand` background)
- Match the icon color to the text it accompanies

### Approved Icon Sources

Icons must be open source and sourced from one of the following:

1. **Lineicons** - https://lineicons.com/free-icons
2. **Bootstrap Icons** - https://icons.getbootstrap.com/#icons
3. **Remix Icon** - https://remixicon.com/

### Usage Guidelines

- Icons should accompany labels, not replace them
- Use icons consistently (same source throughout the application)
- Ensure icons are semantically appropriate for their context
- Test icon legibility at the specified size constraints

### Strict Rules - Icons

**STRICT RULES:**
- ❌ **NO FILL ICONS** - Line icons only
- ❌ **NO MULTI-COLOR ICONS** - Single color only
- ❌ **NO OVERSIZED ICONS** - Maximum 120% of adjacent text height
- ✅ Use icons sparingly and purposefully
- ✅ Source from approved open source libraries only

---

## Technology Stack

### HTML
- Plain, semantic HTML5
- No templating engines
- No frameworks

### CSS
- Plain vanilla CSS
- No preprocessors (no Sass, Less, PostCSS)
- No CSS frameworks (no Bootstrap, Tailwind, etc.)
- CSS in separate `.css` files for caching

### JavaScript
- Plain vanilla JavaScript (ES6+ is fine)
- No frameworks (no React, Vue, Angular)
- No libraries (no jQuery, Lodash, etc.)
- JS in separate `.js` files for caching

### File Organization

**CSS Strategy:**
- Start with one global `styles.css` for entire application
- Add page-specific CSS files only when a page has substantial unique styles
- Layer them: load global first, then page-specific if needed

**Example:**
```html
<link rel="stylesheet" href="styles.css">
<link rel="stylesheet" href="dashboard.css"> <!-- Only if needed -->
```

**JavaScript:**
- Separate `.js` files (not inline)
- Link at end of `<body>` or use `defer`

---

## UI Elements & Components

### Buttons

**Style:**
- Subtle rounded corners: `border-radius: 4-6px` (just a hint of curve)
- Solid backgrounds (no gradients)
- Good padding for touch targets

**Primary Button:**
- Background: `--brand` (#F59E0B)
- Text: White (#FFFFFF)
- Weight: 400

**Secondary Button:**
- Background: White
- Text: `--brand`
- Border: 1-2px solid `--brand`

### Form Inputs

**Style:**
- Clean, modern appearance
- Clear borders
- Good padding (comfortable to use)
- Clear focus states (use `--brand` color)

**Example styling:**
- Border: 1-2px solid `--border-base`
- Focus border: `--brand`
- Padding: 10-12px
- Font: Archivo Narrow 400

### Spacing

**General Rule:** Generous whitespace throughout the application

- Don't cram elements together
- Use comfortable padding and margins
- Let content breathe
- Make touch targets large enough for mobile

### Tables & Lists

**Style:**
- Clean rows with good spacing
- Border: `--border-base` for subtle lines
- Consider alternating row backgrounds for readability (use `--tint` for subtle distinction)
- Ensure mobile responsiveness

### Loading States

- Use simple text messages ("Loading...")
- Or simple spinners (CSS-only, no images)
- Show clear loading indicators for async operations

### Error & Success Messages

**Error Messages:**
- Color: Red (define a semantic error color)
- Display inline near the relevant field/action
- Clear, helpful text

**Success Messages:**
- Color: Green (define a semantic success color)
- Display inline or at top of form
- Clear confirmation text

---

## Interaction Patterns

### NO MODALS Rule

**STRICT RULE: Never use modal overlays/popups**

Instead:

**For Small/Simple Actions:**
- Use inline expandable sections
- Example: "Add web resource" button expands a form on the same page
- Collapse when done or cancelled

**For Large/Complex Forms:**
- Navigate to a dedicated page
- Example: Voice profile survey, detailed team invitation
- Use browser navigation (back button works)

### Confirmations

For destructive actions (delete, remove):
- Use inline confirmation UI
- Show "Are you sure?" message with Yes/No buttons
- Or expand a confirmation section
- Never use `confirm()` dialogs or modals

---

## Responsive Design

**Requirement:** All pages must be fully responsive and work on mobile devices

**Approach:**
- Mobile-first design preferred
- Use flexible layouts (flexbox, grid)
- Ensure touch targets are large enough (min 44x44px)
- Test on various screen sizes

**Navigation on Mobile:**
- Consider hamburger menu or collapsing navigation for primary nav
- Ensure dropdown from email works well on mobile

**Forms on Mobile:**
- Stack form fields vertically
- Full-width inputs on small screens
- Easy-to-tap buttons

---

## Accessibility

While not explicitly discussed, maintain good practices:
- Semantic HTML
- Proper heading hierarchy
- Alt text for images
- Keyboard navigation support
- Sufficient color contrast (our black/white rule helps)
- ARIA labels where needed

---

## Browser Support

- Modern evergreen browsers (Chrome, Firefox, Safari, Edge)
- ES6+ JavaScript is acceptable
- No need to support IE11

---

## Summary of Strict Rules

1. ❌ **NO GRADIENTS** anywhere
2. ❌ **NO MODALS/POPUPS** - use inline expandable or new pages
3. ❌ **NO GREY TEXT** - only black or white text
4. ❌ **NO FRAMEWORKS** - vanilla HTML/CSS/JS only
5. ✅ **CONSISTENT FONT** from approved list
6. ✅ **GENEROUS WHITESPACE** in all layouts
7. ✅ **FULLY RESPONSIVE** for mobile devices
8. ✅ **SEPARATE CSS/JS FILES** for caching
9. ✅ **COLOR PALETTE** - use defined colors consistently

---

**Document Version:** 1.0
**Last Updated:** 2025-11-09
**Status:** Active - Use for all frontend development
