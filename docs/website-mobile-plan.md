# Website mobile remediation

Audit of `apps/website` at phone widths, and the fixes that came out of it. Every page in
`src/router.ts` was rendered in headless Chromium at 375×667 and 390×844 with touch
emulation, plus a width sweep from 320px to 900px. Measurements are from those runs.

## How the problem was shaped

`src/styles/main.scss` has three responsive breakpoints — `900px`, `640px`, `400px` — all
appended as a flat override list at the bottom of the file. Mobile was not a property of each
block; it was a separate list of selectors that someone had to remember to extend. Every
defect below was that list falling out of sync with the 540 lines above it. The Inka pages,
the product bands, and the docs shell all landed after the override block was written and were
never added to it.

The fixes below stay inside that structure. Moving each breakpoint's rules next to the block
they modify is still worth doing and is listed under "Not done" — without it, the next page
added repeats this.

## Fixed

### The homepage app grid broke on every phone width

The app grid is the site's primary product navigation. It was broken at every phone width in
two independent ways.

`.home-page__app-card--flagship` set `grid-column: span 2` and the `640px` block never reset
it — while that same block collapsed the grid to one column. `span 2` in a one-column grid
forces an implicit second column, so the grid computed as `64px 278px`. The three flagship
cards spanned both and looked fine; Upscale and Cutout fell into the two real columns, and
**Upscale rendered 64px wide at every phone width**, name and copy unreadable. The page gained
up to 122px of horizontal scroll, which dragged the fixed header out with it.

Separately, `.home-page__app-card` was `grid-template-columns: auto minmax(0, 1fr)` and never
stacked. At 390px the 128px icon, 32px gap and 2×32px padding consumed 224px, leaving 134px
for three lines of copy — taglines wrapped one or two words per line.

| Viewport | Overflow before | Overflow after | Copy column before | after |
| --- | --- | --- | --- | --- |
| 320px | +122px | none | 64px | 224px |
| 360px | +82px | none | 104px | 264px |
| 375px | +68px | none | 119px | 279px |
| 390px | +52px | none | 134px | 294px |
| 414px | +28px | none | 158px | 318px |
| 430px | +13px | none | 174px | 334px |
| 700px | +4px | none | 154px | 348px |

The same card squeeze also hit the 641–900px range, where the grid stays two-up and the
non-flagship cards are half-width. Those cards now stack too; flagship cards keep the
side-by-side layout, which they have the width for.

### Product bands showed the image before its own heading

`.product-page__band--image-left .product-page__band-copy { order: 2 }` is a desktop
side-by-side swap. The `900px` block collapsed the band to one column but never reset `order`,
so on mobile the artwork rendered above the heading it belonged to — `/inka` bands 1 and 3,
`/fekthor` band 5. `features-page` already reset this exact pattern at 900px;
`product-page` was missed. Now reset alongside it.

### Repeated character art

`/inka` rendered the same 998 KB mascot five times, each in a 420px `min-height` block — 2,100px
of identical artwork on a page already 12.6 screens long. The cut-out is a desktop side-panel
device and is `aria-hidden`, so it is now hidden below 640px. `/inka` dropped from 10,668px to
8,962px at 390px.

### The docs sidebar buried every docs page

`DocsShell.vue` renders `<aside>` before `<article>`, so below 400px all eight nav links stacked
full-width above the page title — every docs page opened on a nav list. Content now orders
above the sidebar, and the nav reads as "other docs" underneath the article.

### Touch targets and type size

| Element | Before | After |
| --- | --- | --- |
| `.site-footer__link` × 9 | 21px | 44px |
| `.pill-header__brand` | 29px | 44px |
| `.site-footer__brand` | 31px | 44px |
| `.pill-header__link` | 32px | 44px |
| `.icon-gallery__category` | 22px | 44px |

The `640px` block already did this for `.pill-header__toggle`; it was never extended to the
nav links, the footer links, either brand link, or the gallery filters. Links keep their type
size and grow through padding, so only the touch area changed.

`.icon-gallery__name`, `.icon-matrix__label` and `.icon-matrix__corner-label` were 10.2px
(`--font-size-xs × 0.85`) and are now `--font-size-xs` (12px) on phones.

Across all 20 routes, sub-44px targets went from 11–15 per page to 0 on 16 routes. What remains
is inline prose links inside paragraphs (`/privacy`, `/terms`, `/acknowledgements`), which are
not standalone tap targets — enlarging them would break the line box.

### Image loading

`loading="lazy"` was applied to 5 of 11 images on `/inka`, 8 of 15 on `/imagekid`, and 0 of 11
on the homepage. Below-the-fold images now lazy-load consistently with `decoding="async"`, and
intrinsic `width`/`height` are set on the fixed-source images that were missing them
(`app/workspace.jpg` 2000×1256, `fekthor/home.jpg` 2000×1378, the 1600×1600 product heroes), so
they no longer shift layout as they load.

### Platform polish

- `theme-color` was hardcoded to the light ground, so iOS Safari's chrome stayed light while
  the site was dark. It now follows the resolved theme, set both by the first-paint inline
  script in `index.html` and by `useColorMode`'s `apply()`.
- No `env(safe-area-inset-*)` existed anywhere. The header now insets for the landscape notch
  and the footer for the home indicator. The insets resolve to zero elsewhere, so no breakpoint
  is involved — note that the `640px` footer `padding` shorthand has to carry the bottom inset
  explicitly or it resets it.
- Inka was missing from the header nav despite being a flagship app with its own page,
  alongside ImageKid and Fekthor which were both listed. Added.

## Not done

- **Responsive image sources.** 10.5 MB across 37 files in `public/media`, still served at
  desktop resolution: `app/workspace.jpg` is 2000px into a 316px slot (6.3×), the 512px brand
  icons render at 64px (8×), and `character/fekthor.png` is 1.3 MB. There is no `srcset`,
  `sizes`, WebP or AVIF anywhere. Fixing this properly means generating variants at two or
  three widths and wiring them into the build — a separate piece of work from the layout fixes
  here, and the largest remaining mobile win.
- **`PillHeader` nav items are `<a>` without `href`.** Navigation works through a click
  handler, so long-press "Open in new tab" and keyboard focus do not. Upstream fix in `@sil/ui`.
- **The open nav menu does not lock body scroll** and has no scrim; the page scrolls behind the
  panel. Also `@sil/ui`.
- **Upscale and Cutout are still footer-only** in the navigation. Left as an IA decision rather
  than assumed.
- **The breakpoint restructure.** Move each breakpoint's rules next to the block they modify.

## Verification

`npm run check` passes — typecheck clean, 20 tests, build succeeds.

After the fixes, all 20 routes report `scrollWidth == clientWidth` at both 375px and 390px, and
the width sweep is clean from 320px to 900px. The remaining flagged "overflow" entries are
`overflow: hidden` bleeds that are intentional (`.app-hero__shot`, `.product-page__band-character`)
and `.sr-only`, none of which produce page scroll.

The audit script renders every route at two phone viewports and reports horizontal overflow,
sub-44px tap targets, sub-13px text, and clipped containers. Worth wiring into `npm run check`
as a regression guard — the `span 2` bug would have been caught the day it shipped.
