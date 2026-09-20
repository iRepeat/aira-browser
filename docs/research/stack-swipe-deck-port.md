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
| `depthScale(relPos)` | `resolveCard().scale` | Upstream decays the left cards `0.98 -> 0.96` and ramps the trailing ones *past* the focused card, `0.98 -> 1.0`. In Aira the focused card is `1.0`, the cards in front of it are `1.0` too, and each level *behind* it is `0.96x` smaller (see below). |
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
- **Tab list mutation, and the card-removal rule Aira had to invent.** Upstream has none of this. Its
  list is an immutable `List<BackStackEntry>` owned by the caller, `maxScrollIndex` is derived from
  `backStack.size - 1`, and its gesture layer only ever implements direction `0` (horizontal): the
  vertical branch of `when (dragDirection)` is absent, so a swipe up does nothing there, and
  `onDismiss` closes the whole overlay rather than removing a card. There is therefore no upstream
  algorithm to port for "what happens to the other cards after one is closed".

  The rule Aira uses follows from the deck's own geometry, where a card's place is its slot against
  the deck scalar. Removing card *k* keeps the focused tab focused (its slot moves with the scalar,
  so it does not move), and every card beyond *k* — away from the focus — moves exactly one slot
  towards the focus, filling the gap in a cascade. Cards between *k* and the focus do not move. When
  the focused card itself is removed the successor takes the focus, or the predecessor when it was
  the last card; that is exactly what `reconcilePosition` resolves against the shorter list. Closing
  either outermost card moves nothing at all: the fan simply loses that slot, which is also why no
  single deck-position animation can do this job — that would move every card uniformly, and uniform
  movement is only correct when the removed card is an end card.
- **A removed card's slot cannot be read from the `ForEach` item.** `ForEach` reuses a node whose key
  is unchanged without running the item builder again, so the item captured by that card's builder
  keeps the index it was created with — the same reuse that made a key of tab id alone leave a card on
  its pending placeholder. Reading the slot from `item.index` therefore left every surviving card on
  its old slot: the gap never closed, and a tab opened later landed on top of the last card. The deck
  records slots in `deckSlotIndexById`, keyed by tab id, and every card reads its slot, layer order and
  geometry from there.
- **A dismissal animates the slot, not the item order.** The closed card stays in the list as a ghost
  while one `animateTo` moves both pieces of observed state into the shape the shorter list will have:
  the deck scalar to the new focus, and the recorded slots to the new order. Cards the removal does not
  shift keep both values and therefore do not move. The commit then publishes the same values, so
  dropping the ghost and re-indexing moves nothing. A timer owns the commit rather than the animation's
  completion callback, both because the end state is identical and because a dismissal that never
  committed would leave the deck holding a ghost and refusing every touch.
- **Depth is size, and only the stack behind the focus is smaller.** Upstream's `depthScale` puts the
  focused card at `0.98` and ramps the trailing cards up to `1.0`, so the biggest card in the deck was
  the one just right of the focus and every card *grew* as it left the centre while *shrinking* on its
  way in — the opposite of a stack, and only a 4% band, so a swipe barely read as depth at all. In
  Aira the focused card is the standard size, so is every card in front of it, and every card behind
  it is `0.96x` the level in front — floored at the third level, the deepest one the left fade still
  shows. Swiping therefore grows a card into the standard size as it reaches the centre and shrinks it
  back into the stack as it passes, and the cards in front never change size as the deck moves. Only
  the scale changed: the left peek series, the trailing parallax, the fades and the fixed z-order are
  upstream's.
- **Deck identity.** Upstream derives cards from the back stack. Aira filters by tab section and by
  locally removed tabs, and keys each card by tab id plus preview identity so a late snapshot
  rebuilds the card instead of leaving the pending placeholder in place. The key deliberately omits
  the card index: including it would rebuild every later card whenever one tab closes, which is also
  why the slot has to come from recorded state rather than from the item.
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
  therefore doubled (the card's slot, times two) and the morph holds `slot * 2 + 1`: strictly above the
  covered card, strictly below its successor, with no tie to break. A card that is leaving the deck
  takes the top slot instead, so closing it cannot trade places with the cards that are moving behind
  it. The slot holder stays mounted while empty,
  so the deck's child list never changes mid-entry, and the morph's own 20/25 z-index is zeroed while
  it sits in that slot so it cannot flatten above every card. The deck keeps `clip(true)` except while
  a card is in a vertical dismiss flight: the stack would otherwise cut the fly-out at its top edge
  and the card would vanish instead of leaving. Toggling clip at the morph handover is still
  forbidden, because that re-rasterises every card in the same frame the current card is revealed.
  The exit morph still grows back out to the page from above every card, where it belongs.
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
- **The entering morph lands on the painted card, not the unscaled layout slot.** The focused deck
  card rests at `FOCUSED_SCALE` (0.98). Targeting the layout slot (`cardWidth` × `previewHeight`) made
  the snapshot finish 2% larger than the card it was handing off to, so the current card visibly
  shrank one more step after the morph ended. Predicted and measured entry targets now share
  `buildDeckPreviewRect`, which includes that scale.
- **`onAreaChange` cannot describe a deck card.** It reports layout bounds and ignores `translate`,
  `scale` and `transform`, so every deck card would report the same centred rectangle. The deck path
  derives the morph rectangle from the same geometry that paints the card, and ignores the reported
  bounds.
- **Close waits for the fly-out, then the remaining cards fill the slot.** `onSwipeEnd` used to
  unmount the card in the same frame as the release, so a swipe past the dismiss threshold vanished
  instead of flying off. The item now keeps the node and animates the offset that the gesture had been
  moving, so the card continues from the finger instead of restarting at the origin. Deck clip is
  dropped for that flight only, otherwise the stack edge eats the motion. Only after the flight does
  the deck start the fill-in described above, and only after the fill-in is the tab actually removed.
- **The dismissed card leaves at the speed it was thrown.** The flight is `travel / release speed`,
  bounded at both ends, so a flick is gone in a blink and a slow release drifts away — the card keeps
  the finger's momentum instead of playing one fixed duration whatever the gesture did. The bounds are
  what make it usable at the extremes: a literal `travel / speed` would hold a lazily released card on
  screen for seconds, and a violent flick would be over before its fade read. The same value drives the
  node's own implicit animation, the explicit `animateTo` and the timer that commits the removal, so
  the flight, the fade and the fill-in behind it all follow the same flick.

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
