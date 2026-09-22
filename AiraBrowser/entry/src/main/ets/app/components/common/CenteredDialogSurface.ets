import { display } from '@kit.ArkUI';
import { BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  CENTERED_DIALOG_ALERT_WIDTH_RATIO,
  CENTERED_DIALOG_MAX_WIDTH_VP,
  CenteredDialogWidthViewModel
} from '../../../core/browser/CenteredDialogWidthViewModel';

export { CENTERED_DIALOG_MAX_WIDTH_VP };
export const CENTERED_DIALOG_HORIZONTAL_MARGIN_VP: number = 12;
/** Width the PC/large-screen shell gives a tall centered dialog that holds a list. */
export const CENTERED_DIALOG_WIDE_MAX_WIDTH_VP: number = 560;
export const CENTERED_DIALOG_CORNER_RADIUS_VP: number = 28;
export const CENTERED_DIALOG_CONTENT_GAP_VP: number = 16;
export const CENTERED_DIALOG_HORIZONTAL_PADDING_VP: number = 20;
export const CENTERED_DIALOG_TOP_PADDING_VP: number = 22;
export const CENTERED_DIALOG_BOTTOM_PADDING_VP: number = 18;
export const CENTERED_DIALOG_TITLE_FONT_SIZE_FP: number = 20;
export const CENTERED_DIALOG_ACTION_GAP_VP: number = 10;
export const CENTERED_DIALOG_ACTION_HEIGHT_VP: number = 44;
export const CENTERED_DIALOG_ACTION_FONT_SIZE_FP: number = 15;
const CENTERED_DIALOG_WIDTH: string =
  `calc(100% - ${CENTERED_DIALOG_HORIZONTAL_MARGIN_VP * 2}vp)`;
const CENTERED_DIALOG_TALL_HEIGHT: string = 'calc(100% - 48vp)';
const CENTERED_DIALOG_TALL_MAX_HEIGHT_VP: number = 720;
// AlertDialog.width accepts Dimension (not calc expressions) and has no
// constraintSize, so a percentage is the only value that preserves the centered
// 12vp contract on a phone. A percentage is relative to the window, though, so
// the same 90% becomes an absurdly wide alert on a PC/large-screen window. The
// shared width owner keeps the percentage only while it still fits the
// centered-dialog maximum and pins to that maximum otherwise.
const CENTERED_DIALOG_ALERT_WIDTH_PERCENT: Dimension = '90%';

const centeredDialogWidthViewModel: CenteredDialogWidthViewModel = new CenteredDialogWidthViewModel();

/**
 * One opaque surface for every centered dialog. Reads the same floating-surface
 * token the rest of the shell uses, and falls back to the light/dark resource
 * when the theme has not been published yet.
 */
export function resolveCenteredDialogSurfaceColor(): ResourceColor {
  const storedColor = AppStorage.get<string>(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY);
  if (storedColor === undefined || storedColor.length === 0) {
    return $r('app.color.surface_floating_background');
  }
  return storedColor;
}

export type CenteredAlertDialogParams =
  AlertDialogParamWithConfirm | AlertDialogParamWithButtons | AlertDialogParamWithOptions;

/**
 * Resolves the AlertDialog width for the current window so a wide PC/large-screen
 * window does not stretch the alert to the whole viewport.
 */
function resolveCenteredAlertDialogWidth(): Dimension {
  const resolved = centeredDialogWidthViewModel.resolve(readDisplayWidthVp());
  if (resolved.percentBased) {
    return CENTERED_DIALOG_ALERT_WIDTH_PERCENT;
  }
  return resolved.widthVp;
}

function resolveCenteredWideDialogWidth(): Dimension {
  const windowWidthVp = readDisplayWidthVp();
  if (!Number.isFinite(windowWidthVp) || windowWidthVp <= 0 ||
    windowWidthVp * CENTERED_DIALOG_ALERT_WIDTH_RATIO <= CENTERED_DIALOG_WIDE_MAX_WIDTH_VP) {
    return CENTERED_DIALOG_ALERT_WIDTH_PERCENT;
  }
  return Math.min(CENTERED_DIALOG_WIDE_MAX_WIDTH_VP,
    windowWidthVp - CENTERED_DIALOG_HORIZONTAL_MARGIN_VP * 2);
}

/**
 * Width for a wide centered dialog on the PC/large-screen shell.
 *
 * A CustomDialogController caps its own box at 400 vp by default, so a caller that
 * needs a wider surface must widen the controller box as well as the content; the
 * content alone just overflows and gets clipped.
 */
export function resolveWideCenteredDialogWidth(): Dimension {
  return resolveCenteredWideDialogWidth();
}

function readDisplayWidthVp(): number {
  try {
    const defaultDisplay = display.getDefaultDisplaySync();
    const widthPx = defaultDisplay.width;
    const densityPixels = defaultDisplay.densityPixels;
    if (!Number.isFinite(widthPx) || widthPx <= 0 ||
      !Number.isFinite(densityPixels) || densityPixels <= 0) {
      return 0;
    }
    return widthPx / densityPixels;
  } catch (_error) {
    return 0;
  }
}

/** Adds the shared centered-dialog surface without choosing the execution owner. */
export function configureCenteredAlertDialog(params: CenteredAlertDialogParams): CenteredAlertDialogParams {
  params.width = resolveCenteredAlertDialogWidth();
  params.cornerRadius = CENTERED_DIALOG_CORNER_RADIUS_VP;
  params.backgroundColor = resolveCenteredDialogSurfaceColor();
  params.backgroundBlurStyle = BlurStyle.NONE;
  return params;
}

/** Applies the shared solid surface while retaining AlertDialog's native behavior. */
export function showCenteredAlertDialog(params: CenteredAlertDialogParams): void {
  AlertDialog.show(configureCenteredAlertDialog(params));
}

class CenteredDialogSurfaceModifier implements AttributeModifier<CommonAttribute> {
  private readonly fillHeight: boolean;
  private readonly boundHeight: boolean;
  private readonly contentPadding: boolean;
  private readonly paddingTop: number;
  private readonly paddingBottom: number;
  private readonly definiteWidth: boolean;

  constructor(
    fillHeight: boolean,
    boundHeight: boolean = false,
    contentPadding: boolean = false,
    paddingTop: number = CENTERED_DIALOG_TOP_PADDING_VP,
    paddingBottom: number = CENTERED_DIALOG_BOTTOM_PADDING_VP,
    definiteWidth: boolean = false
  ) {
    this.fillHeight = fillHeight;
    this.boundHeight = boundHeight;
    this.contentPadding = contentPadding;
    this.paddingTop = paddingTop;
    this.paddingBottom = paddingBottom;
    this.definiteWidth = definiteWidth;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    // Content that itself wraps a Navigation/Scroll has no intrinsic width, so a
    // percentage here resolves against an indeterminate parent and the dialog
    // collapses to its content. Those surfaces take the same definite width the
    // AlertDialog path already resolves instead of the calc() expression. The
    // wide variant uses the PC dialog width rather than the phone alert width.
    instance.width(this.definiteWidth ? resolveCenteredWideDialogWidth() : CENTERED_DIALOG_WIDTH)
    if (this.fillHeight) {
      instance.height(CENTERED_DIALOG_TALL_HEIGHT)
      instance.constraintSize({
        maxWidth: this.definiteWidth ? CENTERED_DIALOG_WIDE_MAX_WIDTH_VP : CENTERED_DIALOG_MAX_WIDTH_VP,
        maxHeight: CENTERED_DIALOG_TALL_MAX_HEIGHT_VP
      })
    } else if (this.boundHeight) {
      instance.constraintSize({
        maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP,
        maxHeight: CENTERED_DIALOG_TALL_HEIGHT
      })
    } else {
      instance.constraintSize({ maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP })
    }
    instance.borderRadius(CENTERED_DIALOG_CORNER_RADIUS_VP)
    instance.clip(true)
    instance.backgroundColor(resolveCenteredDialogSurfaceColor())
    if (this.contentPadding) {
      instance.padding({
        left: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        right: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        top: this.paddingTop,
        bottom: this.paddingBottom
      })
    }
  }
}

export const CENTERED_DIALOG_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true);
export const CENTERED_DIALOG_COMPACT_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true, 16, 12);
export const CENTERED_DIALOG_TALL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true);
export const CENTERED_DIALOG_TALL_PADDED_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true, false, true);
export const CENTERED_DIALOG_SCROLL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, true);
export const CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true);
export const CENTERED_DIALOG_SYSTEM_COMPACT_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true, 16, 12);
export const CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true);
// Same tall surface, but with a definite width for content that has no intrinsic width
// (a wrapped Navigation or Scroll) and would otherwise collapse narrower than its peers.
export const CENTERED_DIALOG_SYSTEM_TALL_DEFINITE_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true, false, false, CENTERED_DIALOG_TOP_PADDING_VP,
    CENTERED_DIALOG_BOTTOM_PADDING_VP, true);
export const CENTERED_DIALOG_SYSTEM_TALL_PADDED_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true, false, true);
export const CENTERED_DIALOG_SYSTEM_SCROLL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, true);

@Component
export struct CenteredDialogSurface {
  @Prop fillHeight: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    if (this.fillHeight) {
      this.buildTallSurface()
    } else {
      this.buildCompactSurface()
    }
  }

  @Builder
  private buildCompactSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .attributeModifier(new CenteredDialogSurfaceModifier(false, false, true))
  }

  @Builder
  private buildTallSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .attributeModifier(new CenteredDialogSurfaceModifier(true))
  }

  @Builder
  private emptyContent() {
  }
}
