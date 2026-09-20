# StackSwipe deck port

Aira's horizontal tab overview is a stacked deck instead of a flat strip. Its geometry and physics
are ported from [SoxiaLiSA/StackSwipe](https://github.com/SoxiaLiSA/StackSwipe), an MIT-licensed
Jetpack Compose app switcher.

- Upstream file: `app/src/main/java/ceui/lisa/stackswipe/appswitcher/AppSwitcherOverlay.kt`
- Pinned commit: `829894591cd0040b02aff7d2fa2f6bfc365f12de`
- License: MIT. The upstream repository declares "MIT License. Use it, modify it, ship it." in its
  README and does not ship a separate `LICENSE` file. The copyright notice and permission notice are
  reproduced below as MIT requires.

## What was reused

Only arithmetic. The upstream file is Compose UI, so no Kotlin is compiled, linked, or transliterated
statement by statement into Aira. The port keeps the upstream constant names, values, and formulas,
and re-expresses them as pure functions in ArkTS.

The ported source lives in
`AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy.ets`
and `BrowserTabsOverviewStackMotion.ets`, with ArkUI wiring in
`AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets`.

| Upstream | Aira | Notes |
| --- | --- | --- |
| `cardCenterX(index, sp)` | `BrowserTabsOverviewStackLayoutPolicy.resolveCard().offsetX` | Offset from the deck centre instead of the screen centre, so the caller owns the sheet geometry. |
| `depthScale(relPos)` | `resolveCard().scale` | Left cards decay `0.98 -> 0.96`; focused and trailing cards ramp `0.98 -> 1.0`. |
| `overscrollSinkScale(index)` | folded into `resolveCard().scale` | Right-edge overscroll sinks the cards that trail the focus. |
| `leftFadeAlpha`, `titleAlpha`, `titleBlurRadius`, `darkOverlayAlpha` | `opacity`, `titleOpacity`, `shadeOpacity` | `shadeOpacity` is painted as a black overlay on the card. `titleAlpha` becomes `titleOpacity`; upstream's companion `titleBlurRadius` is not ported (see below). |
| `Modifier.zIndex(index)` | `zIndex` | Fixed draw order by tab index, so trailing cards cover leading ones. |
| `onDrag` | `advanceDrag` | `0.70` base friction, then `0.6 / (1 + overscroll * 0.5)` edge resistance. |
| `onDragEnd` | `release` | `velocityInIndex = -velocityX / (width * 0.60)`, then `position + velocityInIndex * 0.25` rounded to a card. An overscrolled release keeps the projected card but drops the initial velocity. |
| `spring(stiffness = 80f, DampingRatioNoBouncy, visibilityThreshold = 0.0005f)` | `sampleSpring` | Closed-form critically damped solution, sampled once per display frame. The cancel path uses `Spring.StiffnessLow` (200) through `SPRING_CANCEL_STIFFNESS`; the release path uses the literal `80`. Rest requires both the displacement and the velocity under `visibilityThreshold`. |

## Deliberate differences

- **No drag-direction gate.** Upstream spends its first 15px deciding between horizontal scroll and
  vertical dismissal. Aira's cards already own an upward close gesture, so the deck's horizontal
  `PanGesture` and the card's vertical one arbitrate through ArkUI.
- **A one-per-frame position owner.** Upstream keeps two scalars (`dragScrollPos`, `animScrollPos`)
  and switches between them. `BrowserTabsOverviewStackMotion` keeps one scalar, so a drag that starts
  during settling continues from the displayed value instead of a stale endpoint.
- **Per-frame geometry.** Upstream recomposes Compose with the animated scalar and re-evaluates the
  nonlinear layout each frame. ArkUI's `animateTo` would interpolate only the endpoint transforms and
  cut straight through the deck spacing, so the deck samples the spring on
  `UIContext.postFrameCallback` and publishes the scalar that every card's geometry is derived from.
- **Tab list mutation.** Upstream re-snaps to `state.selectedIndex`. Aira can also close a tab from
  the deck, so `reconcilePosition` keeps the anchored tab focused, hands its slot to the successor
  when the anchored tab itself disappears, and preserves the fractional part of an in-flight drag.
- **Deck identity.** Upstream derives cards from the back stack. Aira filters by tab section and by
  locally removed tabs, and keys each card by tab id plus preview identity so a late snapshot
  rebuilds the card instead of leaving the pending placeholder in place. The key deliberately omits
  the card index: including it would rebuild every later card whenever one tab closes.
- **Interruption always finishes.** Upstream's gesture owns the whole interaction. Aira's deck can be
  interrupted by non-gesture state (a card's vertical gesture claims the touch, a tab closes, the
  section changes, the layer hides), so `abortDeckMotion` cancels the settle and then settles to the
  nearest card. Stopping alone would park the deck between two cards with no frame left to move it.
- **Screenshot fill.** Upstream draws the screenshot with `ContentScale.FillBounds`. Aira's deck uses
  `ImageFit.Cover`, which fills the card without distorting the page. The grid and the flat strip keep
  their existing `Fill`/`Contain` behaviour.
- **No deck-level expand fade.** Upstream multiplies each card's alpha by `expandFade` during its
  open/close expansion. Aira's shared-snapshot morph already owns that transition, so the deck only
  fades through `leftFadeAlpha`.
- **The title fades through opacity, not blur.** Upstream pairs `titleAlpha` with
  `titleBlurRadius = ((1f - titleAlpha).coerceAtMost(0.5f) * 2f * 10f).dp`, so every card one slot
  from the focus re-blurs its label on each display frame. Aira keeps the same `titleAlpha` tent in
  `titleOpacity` and drops the blur channel entirely: the title transition is carried by opacity
  alone. Blurring text per frame on top of the deck's translate/scale pass costs far more than the
  fade it decorates, and the deck is already the busiest frame in the tab overview.
- **The entering morph is a deck slot, not a layer above the deck.** Upstream has no shared-snapshot
  morph, so it has nothing to say about where one belongs. Aira's entering morph first shipped as an
  overlay above the whole cards layer, which put it above cards it must sit behind: the cards that
  trail the covered one were covered by the snapshot for the whole entry and then took the frame at
  the handover, which read as the target card piercing its right neighbour. The morph now occupies a
  slot *inside* the deck's `Stack`, so its `zIndex` competes with the cards themselves. Card slots are
  therefore doubled (`item.index * 2`) and the morph holds `slot * 2 + 1`: strictly above the covered
  card, strictly below its successor, with no tie to break. The slot holder stays mounted while empty,
  so the deck's child list never changes mid-entry, and the morph's own 20/25 z-index is zeroed while
  it sits in that slot so it cannot flatten above every card. The deck keeps `clip(true)` for its
  whole lifetime: toggling clip at the handover re-rasterises every card in the same frame the current
  card is revealed. The exit morph still grows back out to the page from above every card, where it
  belongs.
- **Entry displacement waits at the origin, then flies in once.** While the morph is still preparing,
  motion duration is 0 and progress is 0: the trailing cards snap off-screen behind an opacity-0 layer.
  When settling starts, duration becomes the 350ms enter animation and progress goes to 1, so the cards
  fly in once. Duration 0 for the whole displacement made ArkUI snap the derived translate to rest;
  duration 350 during prepare made them fly out and reverse. An in-flight progress is never yanked
  back to 0 when `settlingEnabled` drops one `@Watch` before the tab id clears.
- **The covered card stays painted under an in-deck morph.** Zeroing its preview left a hole the frame
  the morph unmounted — the current card vanished and then popped back. The morph already sits one slot
  above that card and covers its preview, so unmount only has to remove the overlay. Morph unmount and
  the covered-tab id clear still land in one presentation publish; the home-reveal settle timer must
  not cut a still-morphing web entry short.
- **`onAreaChange` cannot describe a deck card.** It reports layout bounds and ignores `translate`,
  `scale` and `transform`, so every deck card would report the same centred rectangle. The deck path
  derives the morph rectangle from the same geometry that paints the card, and ignores the reported
  bounds.

## MIT license text

```
MIT License

Copyright (c) SoxiaLiSA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
