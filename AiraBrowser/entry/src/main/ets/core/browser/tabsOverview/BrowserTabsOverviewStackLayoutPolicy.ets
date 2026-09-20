/**
 * Deck geometry and index-space physics ported from SoxiaLiSA/StackSwipe (MIT), file
 * `appswitcher/AppSwitcherOverlay.kt` at commit `829894591cd0040b02aff7d2fa2f6bfc365f12de`.
 *
 * The reference is Compose, so only its arithmetic is reused. Every constant below keeps the
 * reference name and value — except the depth scale, which Aira deliberately turned around so the
 * focused card is the largest one (see `FOCUSED_SCALE`):
 *
 * - `cardCenterX`  -> `resolveCard().offsetX`, measured from the deck centre, not the sheet edge
 * - `depthScale`   -> `resolveCard().scale`, Aira's symmetric decay instead of the reference ramp
 * - `overscrollSinkScale` -> folded into `resolveCard().scale`
 * - `leftFadeAlpha`, `titleAlpha`, `darkOverlayAlpha` -> the remaining metrics. Upstream's
 *   `titleBlurRadius` is deliberately not ported: Aira expresses the title transition through
 *   `titleOpacity` alone instead of re-blurring the label on every display frame.
 * - `onDrag`/`onDragEnd` -> `advanceDrag`/`release`
 * - `spring(stiffness = 80, DampingRatioNoBouncy, visibilityThreshold = 0.0005)` -> `sampleSpring`
 *
 * The deck's own card width, height and centre are supplied by the caller, so this file stays pure
 * and testable outside ArkUI. Provenance, the MIT license text, and the deliberate differences from
 * upstream are recorded in `docs/research/stack-swipe-deck-port.md`.
 */

export interface BrowserTabsOverviewStackCardMetrics {
  /** Horizontal offset from the deck centre, in vp. */
  offsetX: number;
  /**
   * Vertical offset from where the deck centres a card, in vp.
   *
   * Always 0 for the resting deck: every card shares one baseline. It exists for the layouts that
   * place a card against something else — a pull showing the row beside the held card has to line the
   * neighbours up with it.
   */
  offsetY: number;
  scale: number;
  opacity: number;
  titleOpacity: number;
  shadeOpacity: number;
  zIndex: number;
}

export interface BrowserTabsOverviewStackRelease {
  target: number;
  velocity: number;
}

export interface BrowserTabsOverviewStackSpringSample {
  position: number;
  velocity: number;
  finished: boolean;
}

export interface BrowserTabsOverviewStackVisibleRange {
  first: number;
  last: number;
}

/** Reference: `leftBasePeek = cardWidthPx * 0.22f`. */
const LEFT_BASE_PEEK_RATIO: number = 0.22;
/** Reference: `leftDecay = 0.28f`. */
const LEFT_DECAY: number = 0.28;
/** Reference: `rightSpacingPx = cardWidthPx * 0.85f`. Also scales the elastic overscroll. */
const RIGHT_SPACING_RATIO: number = 0.85;
/** Reference: `dragSpacingPx = cardWidthPx * 0.60f`. Converts pixels to index space. */
const DRAG_SPACING_RATIO: number = 0.60;
/** Reference: `baseFriction = 0.70f`. */
const DRAG_BASE_FRICTION: number = 0.70;
/** Reference: `0.6f / (1f + overscrollAmount * 0.5f)`. */
const EDGE_FRICTION_START: number = 0.6;
const EDGE_FRICTION_DECAY: number = 0.5;
/** Reference: `absOver / (1f + absOver * 0.8f)`. */
const OVERSCROLL_DAMPING: number = 0.8;
/** Reference: `velocityInIndex * 0.25f`. */
const RELEASE_PROJECTION_SECONDS: number = 0.25;
/**
 * The focused card is the standard size, and the cards in front of it are the same size.
 *
 * Upstream instead ramps the trailing cards *past* the focus (`0.98 -> 1.0`): the biggest card sat
 * just right of the focus while the focus itself was 0.98, and every card grew as it moved away from
 * the centre and shrank on its way in. Aira keeps the focus at the standard size and lets nothing
 * grow past it, so the size reads as depth rather than as travel: what sits in front of the focus is
 * full size, and what sits behind it steps down one level per card.
 */
const FOCUSED_SCALE: number = 1;
/**
 * Each level *behind* the focus is this much smaller than the level in front of it.
 *
 * Deliberately gentle: the cards behind are already darkened by `shadeOpacity` and mostly hidden
 * behind the card in front, so the size only has to hint at the depth. Three levels of a larger step
 * (0.94, say) left the deepest card a sixth smaller than the focus, which read as shrinking cards
 * rather than as a stack.
 */
const DEPTH_SCALE_STEP: number = 0.96;
/**
 * Levels that stay visually distinct: the left fade is gone by the third card, so nothing beyond it
 * can be seen. The floor keeps a card far down the stack from shrinking without bound.
 */
const DEPTH_VISIBLE_LEVELS: number = 3;
const MIN_DEPTH_SCALE: number = Math.pow(DEPTH_SCALE_STEP, DEPTH_VISIBLE_LEVELS);
/** Reference: `darkOverlayAlpha = (-relPos * 0.25f).coerceAtMost(0.50f)`. */
const SHADE_PER_CARD: number = 0.25;
const SHADE_MAX: number = 0.50;
/** Reference: `overscrollSinkScale` cap of `0.15f`. */
const SINK_DEPTH: number = 0.15;
/** Reference release spring: the literal `stiffness = 80f` in the reference `onDragEnd`.**/
export const SPRING_STIFFNESS: number = 80;
/** Reference cancel spring: `Spring.StiffnessLow` in the reference `onDragCancel`.**/
export const SPRING_CANCEL_STIFFNESS: number = 200;
const SPRING_VISIBILITY_THRESHOLD: number = 0.0005;

export class BrowserTabsOverviewStackLayoutPolicy {
  /** Reference: `scrollPos.coerceIn(0f, maxScrollIndex)`. */
  clamp(position: number, count: number): number {
    return Math.max(0, Math.min(this.resolveMaxIndex(count), this.finite(position)));
  }

  resolveMaxIndex(count: number): number {
    return Math.max(0, Math.floor(this.finite(count)) - 1);
  }

  /**
   * Cards worth building for the current scalar.
   *
   * The reference culls at `relPos <= -3` (fully faded) and at one card width past each screen
   * edge, drawing trailing cards at `relPos^1.2 * width * 0.85`. Inverting that curve gives the last
   * card that can still be inside the viewport, so the deck never builds a card that cannot be seen
   * and never drops one that is still animating in.
   */
  resolveVisibleRange(position: number, count: number, viewportWidth: number,
    cardWidth: number): BrowserTabsOverviewStackVisibleRange {
    const maxIndex = this.resolveMaxIndex(count);
    if (maxIndex <= 0) {
      return { first: 0, last: maxIndex };
    }
    const clamped = this.clamp(position, count);
    const width = Math.max(1, this.finite(cardWidth));
    const reach = Math.max(0, this.finite(viewportWidth)) / 2 + width;
    const rightBound = Math.pow(reach / (width * RIGHT_SPACING_RATIO), 1 / 1.2);
    return {
      first: Math.max(0, Math.floor(clamped) - 3),
      last: Math.min(maxIndex, Math.ceil(clamped) + Math.max(0, Math.ceil(rightBound)))
    };
  }

  /**
   * Reference: `cardCenterX` + `depthScale` + `overscrollSinkScale` + the four fade terms, with Aira's
   * own depth scale.
   * `cardWidth` is the reference's `cardWidthPx`; the caller subtracts half a card to get a left
   * edge, exactly like `baseX - cardWidthPx / 2f`.
   */
  resolveCard(
    index: number,
    position: number,
    count: number,
    cardWidth: number
  ): BrowserTabsOverviewStackCardMetrics {
    if (!Number.isFinite(index)) {
      // No identity for this card, so nothing can be placed. Report it fully transparent instead
      // of silently painting card 0 in its slot.
      return {
        offsetX: 0,
        offsetY: 0,
        scale: 0,
        opacity: 0,
        titleOpacity: 0,
        shadeOpacity: 0,
        zIndex: 0
      };
    }
    const cardCount = this.resolveCardCount(count);
    const width = Math.max(1, this.finite(cardWidth));
    const raw = this.finite(position);
    const clamped = this.clamp(raw, count);
    // Reference: `overscroll = sp - cSp`, negative past the left edge and positive past the right.
    const overscroll = raw - clamped;
    const relPos = this.finite(index) - clamped;
    const leftDistance = Math.max(0, -relPos);
    const rightDistance = Math.max(0, relPos);

    let baseX = 0;
    if (relPos <= 0) {
      // Reference: `leftBasePeek * (1f - leftDecay.pow(d)) / (1f - leftDecay)`, converging series.
      const series = 1 - Math.pow(LEFT_DECAY, leftDistance);
      baseX = -width * LEFT_BASE_PEEK_RATIO * series / (1 - LEFT_DECAY);
    } else {
      // Reference: `relPos.pow(1.2f) * rightSpacingPx`, the trailing parallax.
      baseX = Math.pow(rightDistance, 1.2) * width * RIGHT_SPACING_RATIO;
    }

    // Reference: `overscrollWeight` differs per edge so the cards fan out instead of moving together.
    let overscrollWeight = 0;
    if (overscroll < 0) {
      const d = Math.max(0, relPos);
      overscrollWeight = 0.72 + 0.55 * (d / (d + 0.6));
    } else if (overscroll > 0) {
      const d = Math.max(0, -relPos);
      overscrollWeight = 0.65 / (d + 1);
    }
    const dampedOverscroll = Math.abs(overscroll) / (1 + Math.abs(overscroll) * OVERSCROLL_DAMPING);
    const offsetX = baseX -
      Math.sign(overscroll) * dampedOverscroll * width * RIGHT_SPACING_RATIO * overscrollWeight;

    // `depthScale(relPos)`: the focus and everything in front of it are the standard size, and only
    // the stack behind it steps down. Swiping a card into the centre grows it; swiping it past the
    // centre shrinks it into the stack, one level per card.
    const depthScale = relPos >= 0 ?
      FOCUSED_SCALE :
      Math.max(MIN_DEPTH_SCALE, FOCUSED_SCALE * Math.pow(DEPTH_SCALE_STEP, leftDistance));

    // Reference: `overscrollSinkScale(index)`, only past the right edge.
    let sinkScale = 1;
    if (overscroll > 0) {
      const d = Math.max(0, -relPos);
      const sinkWeight = 0.3 + 0.7 * (d / (d + 0.8));
      const damped = overscroll / (1 + overscroll * OVERSCROLL_DAMPING);
      sinkScale = 1 - damped * SINK_DEPTH * sinkWeight;
    }

    // Reference: `leftFadeAlpha`, fully visible at relPos >= -2 and gone by relPos = -3.
    const opacity = Math.max(0, Math.min(1, 3 + relPos));
    // Reference: `titleAlpha = minOf(1f + relPos, 2f - relPos).coerceIn(0f, 1f)`. Upstream then
    // blurs the label by `((1f - titleAlpha).coerceAtMost(0.5f) * 2f * 10f).dp`; Aira fades the
    // title through this single opacity channel instead, so the deck never blurs text per frame.
    const titleOpacity = Math.max(0, Math.min(1, Math.min(1 + relPos, 2 - relPos)));
    // Reference: `if (relPos < 0f) (-relPos * 0.25f).coerceAtMost(0.50f) else 0f`.
    const shadeOpacity = relPos < 0 ? Math.min(SHADE_MAX, leftDistance * SHADE_PER_CARD) : 0;

    return {
      offsetX: offsetX,
      offsetY: 0,
      scale: depthScale * sinkScale,
      opacity: cardCount <= 0 ? 0 : opacity,
      titleOpacity: titleOpacity,
      shadeOpacity: shadeOpacity,
      // Reference: `Modifier.zIndex(index.toFloat())`, a fixed draw order by tab index.
      zIndex: Math.max(0, Math.floor(this.finite(index)))
    };
  }

  /**
   * Reference `onDrag`: one drag frame in index space.
   *
   * `deltaX` is the finger's movement since the previous frame, so the caller must feed deltas
   * rather than a cumulative offset.
   */
  advanceDrag(position: number, deltaX: number, width: number, count: number): number {
    if (this.resolveCardCount(count) <= 0) {
      return 0;
    }
    // Reference tracks the raw `dragScrollPos`, so overscroll is preserved here too. A single card
    // still rubber-bands and springs back, exactly like the reference's one-page case.
    const clamped = this.clamp(position, count);
    if (!Number.isFinite(deltaX) || !Number.isFinite(position) || !Number.isFinite(width) ||
      width <= 0) {
      return clamped;
    }
    const maxIndex = this.resolveMaxIndex(count);
    // Reference: `val delta = -dragAmount.x / dragSpacingPx`.
    const delta = -deltaX / (width * DRAG_SPACING_RATIO);
    // Reference: `overscrollAmount`, measured before the update, not after.
    const overscrollAmount = position < 0 ? -position : (position > maxIndex ? position - maxIndex : 0);
    const isOverscrolling = (position <= 0 && delta < 0) || (position >= maxIndex && delta > 0);
    const edgeFriction = isOverscrolling ?
      EDGE_FRICTION_START / (1 + overscrollAmount * EDGE_FRICTION_DECAY) : 1;
    // Reference adds to the raw `dragScrollPos`, so the overscroll itself is preserved.
    return position + delta * DRAG_BASE_FRICTION * edgeFriction;
  }

  /**
   * Reference `onDragEnd`: project the release with the tracker velocity and snap to that card.
   * Overscrolling only discards the initial velocity, exactly like the reference's
   * `initialVelocity = if (isOverscrolled) 0f else velocityInIndex`; the projected card is still
   * where the deck lands.
   */
  release(position: number, velocityX: number, width: number, count: number): BrowserTabsOverviewStackRelease {
    const maxIndex = this.resolveMaxIndex(count);
    const validVelocity = Number.isFinite(velocityX) && Number.isFinite(width) && width > 0;
    const velocityInIndex = validVelocity ? -velocityX / (width * DRAG_SPACING_RATIO) : 0;
    const projected = this.finite(position) + velocityInIndex * RELEASE_PROJECTION_SECONDS;
    const target = Math.max(0, Math.min(maxIndex, Math.round(projected)));
    const isOverscrolled = this.finite(position) < 0 || this.finite(position) > maxIndex;
    return {
      target: this.resolveCardCount(count) <= 0 ? 0 : target,
      velocity: isOverscrolled || !validVelocity ? 0 : velocityInIndex
    };
  }

  /**
   * Reference: `spring(dampingRatio = DampingRatioNoBouncy, stiffness, visibilityThreshold =
   * 0.0005f)`. The reference uses two stiffnesses: the literal `80f` on drag release and
   * `Spring.StiffnessLow` (200) on drag cancel.
   *
   * Both are critically damped, so the analytic solution for `x'' + 2w x' + w^2 x = 0` with
   * `w = sqrt(stiffness)` is exact and needs no numerical integration. Sampling a scalar and
   * evaluating the card geometry per frame keeps the nonlinear deck spacing on the real path;
   * animating only the endpoints would interpolate straight through it.
   *
   * `DampingRatioNoBouncy` means the deck never overshoots its target: the displacement decays to
   * zero monotonically, so cards come to rest rather than bouncing past their slot.
   */
  sampleSpring(
    start: number,
    target: number,
    velocity: number,
    elapsedSeconds: number,
    stiffness: number = SPRING_STIFFNESS
  ): BrowserTabsOverviewStackSpringSample {
    const t = Math.max(0, this.finite(elapsedSeconds));
    const from = this.finite(start);
    const to = this.finite(target);
    const initialVelocity = this.finite(velocity);
    const omega = Math.sqrt(Math.max(1, this.finite(stiffness)));
    const displacement = from - to;
    const coefficient = initialVelocity + omega * displacement;
    const decay = Math.exp(-omega * t);
    const remaining = (displacement + coefficient * t) * decay;
    const speed = (coefficient - omega * (displacement + coefficient * t)) * decay;
    // Compose's `SpringSimulation.isAtEquilibrium` requires both the displacement and the velocity
    // to fall under `visibilityThreshold`, so an in-threshold displacement with live velocity is
    // still moving and must keep sampling.
    if (Math.abs(remaining) < SPRING_VISIBILITY_THRESHOLD &&
      Math.abs(speed) < SPRING_VISIBILITY_THRESHOLD) {
      return { position: to, velocity: 0, finished: true };
    }
    return { position: to + remaining, velocity: speed, finished: false };
  }

  /**
   * Keep the card under the finger when the tab list changes.
   *
   * Reference re-snaps to `state.selectedIndex`; Aira also supports closing a tab from the deck, so
   * the focus has to survive a removal. When the anchored tab itself disappears its successor takes
   * the same slot, and the last card falls back to its predecessor.
   */
  reconcilePosition(position: number, previousIds: string[], nextIds: string[]): number {
    if (nextIds.length === 0) {
      return 0;
    }
    const maxIndex = this.resolveMaxIndex(nextIds.length);
    const anchorIndex = Math.max(0, Math.min(this.resolveMaxIndex(previousIds.length),
      Math.round(this.finite(position))));
    const anchorId = previousIds[anchorIndex];
    const nextIndex = anchorId === undefined ? -1 : nextIds.indexOf(anchorId);
    if (nextIndex < 0) {
      return Math.max(0, Math.min(maxIndex, anchorIndex));
    }
    // Preserve the fractional part so an in-flight drag keeps its sub-card offset.
    return Math.max(0, Math.min(maxIndex, nextIndex + this.finite(position) - anchorIndex));
  }

  private resolveCardCount(count: number): number {
    return Number.isFinite(count) && count > 0 ? Math.floor(count) : 0;
  }

  private finite(value: number): number {
    return Number.isFinite(value) ? value : 0;
  }
}
