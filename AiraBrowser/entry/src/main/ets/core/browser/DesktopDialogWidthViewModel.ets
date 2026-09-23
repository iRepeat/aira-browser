import {
  DESKTOP_DIALOG_ACTION_LABEL_PADDING_VP,
  DESKTOP_DIALOG_ACTION_LABEL_UNIT_VP,
  DESKTOP_DIALOG_CORNER_RADIUS_VP,
  DESKTOP_DIALOG_EDGE_VP,
  DESKTOP_DIALOG_HEIGHT_CAP_VP,
  DESKTOP_DIALOG_NARROW_CORNER_RADIUS_VP,
  DESKTOP_DIALOG_NARROW_PADDING_VP,
  DESKTOP_DIALOG_NARROW_WINDOW_VP,
  DESKTOP_DIALOG_PADDING_VP,
  DESKTOP_DIALOG_STACK_ACTIONS_WINDOW_VP,
  DESKTOP_DIALOG_STEP_DOWN_WINDOW_VP,
  DesktopDialogTier,
  desktopDialogTierSpec
} from './BrowserDialogPresentationTokens';

export type DesktopDialogActionLayout = 'row' | 'stack';

export class DesktopDialogLayout {
  readonly tier: DesktopDialogTier;
  readonly widthVp: number;
  readonly maxHeightVp: number;
  readonly cornerRadiusVp: number;
  readonly paddingVp: number;
  readonly fullWidth: boolean;

  constructor(
    tier: DesktopDialogTier,
    widthVp: number,
    maxHeightVp: number,
    cornerRadiusVp: number,
    paddingVp: number,
    fullWidth: boolean
  ) {
    this.tier = tier;
    this.widthVp = widthVp;
    this.maxHeightVp = maxHeightVp;
    this.cornerRadiusVp = cornerRadiusVp;
    this.paddingVp = paddingVp;
    this.fullWidth = fullWidth;
  }
}

/**
 * The only width formula for large-screen centered dialogs.
 *
 * Callers declare a content-shaped tier. This owner resolves the window.
 */
export class DesktopDialogWidthViewModel {
  resolve(tier: DesktopDialogTier, windowWidthVp: number, windowHeightVp: number): DesktopDialogLayout {
    const resolvedTier = this.stepDownTier(tier, windowWidthVp);
    const spec = desktopDialogTierSpec(resolvedTier);
    const edge = DESKTOP_DIALOG_EDGE_VP;
    const usableWidth = this.usableExtent(windowWidthVp, edge);
    const usableHeight = this.usableExtent(windowHeightVp, edge);
    const narrow = this.isNarrow(windowWidthVp);
    let width = spec.widthVp;
    if (narrow && usableWidth > 0) {
      width = usableWidth;
    }
    width = this.clampWidth(width, spec.minWidthVp, usableWidth);
    const heightCap = Math.min(spec.maxHeightVp, DESKTOP_DIALOG_HEIGHT_CAP_VP);
    const maxHeight = usableHeight > 0 ? Math.min(heightCap, usableHeight) : heightCap;
    return new DesktopDialogLayout(
      resolvedTier,
      width,
      maxHeight,
      narrow ? DESKTOP_DIALOG_NARROW_CORNER_RADIUS_VP : DESKTOP_DIALOG_CORNER_RADIUS_VP,
      narrow ? DESKTOP_DIALOG_NARROW_PADDING_VP : DESKTOP_DIALOG_PADDING_VP,
      narrow
    );
  }

  /**
   * 1–2 actions sit side by side unless a label would wrap or the window is
   * narrower than the stack breakpoint. Three or more always stack.
   */
  resolveActionLayout(labels: string[], contentWidthVp: number, windowWidthVp: number): DesktopDialogActionLayout {
    if (labels.length >= 3 || this.shouldStackForWindow(windowWidthVp)) {
      return 'stack';
    }
    if (labels.length <= 1) {
      return 'row';
    }
    const slot = contentWidthVp / labels.length;
    for (let index = 0; index < labels.length; index++) {
      if (this.estimateLabelWidthVp(labels[index]) > slot) {
        return 'stack';
      }
    }
    return 'row';
  }

  estimateLabelWidthVp(label: string): number {
    return label.length * DESKTOP_DIALOG_ACTION_LABEL_UNIT_VP + DESKTOP_DIALOG_ACTION_LABEL_PADDING_VP;
  }

  private stepDownTier(tier: DesktopDialogTier, windowWidthVp: number): DesktopDialogTier {
    if (!Number.isFinite(windowWidthVp) || windowWidthVp <= 0 ||
      windowWidthVp >= DESKTOP_DIALOG_STEP_DOWN_WINDOW_VP) {
      return tier;
    }
    if (tier === 'xl') {
      return 'l';
    }
    if (tier === 'l') {
      return 'm';
    }
    return tier;
  }

  private isNarrow(windowWidthVp: number): boolean {
    return Number.isFinite(windowWidthVp) && windowWidthVp > 0 &&
      windowWidthVp < DESKTOP_DIALOG_NARROW_WINDOW_VP;
  }

  private shouldStackForWindow(windowWidthVp: number): boolean {
    return Number.isFinite(windowWidthVp) && windowWidthVp > 0 &&
      windowWidthVp < DESKTOP_DIALOG_STACK_ACTIONS_WINDOW_VP;
  }

  private usableExtent(windowExtentVp: number, edgeVp: number): number {
    if (!Number.isFinite(windowExtentVp) || windowExtentVp <= 0) {
      return 0;
    }
    return Math.max(0, windowExtentVp - edgeVp * 2);
  }

  private clampWidth(widthVp: number, minWidthVp: number, usableWidthVp: number): number {
    if (usableWidthVp <= 0) {
      return widthVp;
    }
    if (usableWidthVp < minWidthVp) {
      return usableWidthVp;
    }
    return Math.min(Math.max(widthVp, minWidthVp), usableWidthVp);
  }
}
