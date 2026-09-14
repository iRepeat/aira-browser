import {
  FLOATING_GLASS_MATERIAL_THICK_STYLE,
  isFloatingGlassMaterialAvailable
} from './FloatingGlassMaterialTokens';
import {
  applyCommonSystemMaterial,
  assignDialogSystemMaterial,
  createDialogImmersiveMaterial,
  ImmersiveMaterialHandle
} from './ArkUiMaterialAccess';
import { display } from '@kit.ArkUI';
import {
  CENTERED_DIALOG_MAX_WIDTH_VP,
  CenteredDialogWidthViewModel
} from '../../../core/browser/CenteredDialogWidthViewModel';

export { CENTERED_DIALOG_MAX_WIDTH_VP };
export const CENTERED_DIALOG_HORIZONTAL_MARGIN_VP: number = 12;
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

export function createCenteredDialogMaterial(): ImmersiveMaterialHandle | undefined {
  if (!isFloatingGlassMaterialAvailable()) {
    return undefined;
  }
  return createDialogImmersiveMaterial(FLOATING_GLASS_MATERIAL_THICK_STYLE);
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
/** Adds the shared API 26 presentation parameters without choosing the execution owner. */
export function configureCenteredAlertDialog(params: CenteredAlertDialogParams): CenteredAlertDialogParams {
  params.width = resolveCenteredAlertDialogWidth();
  params.cornerRadius = CENTERED_DIALOG_CORNER_RADIUS_VP;
  assignDialogSystemMaterial(params, createCenteredDialogMaterial());
  return params;
}

/** Applies the shared API 26 material contract while retaining AlertDialog's native behavior. */
export function showCenteredAlertDialog(params: CenteredAlertDialogParams): void {
  AlertDialog.show(configureCenteredAlertDialog(params));
}

class CenteredDialogSurfaceModifier implements AttributeModifier<CommonAttribute> {
  private readonly fillHeight: boolean;
  private readonly boundHeight: boolean;
  private readonly contentPadding: boolean;
  private readonly paddingTop: number;
  private readonly paddingBottom: number;
  private readonly materialEnabled: boolean;

  constructor(
    fillHeight: boolean,
    boundHeight: boolean = false,
    contentPadding: boolean = false,
    paddingTop: number = CENTERED_DIALOG_TOP_PADDING_VP,
    paddingBottom: number = CENTERED_DIALOG_BOTTOM_PADDING_VP,
    materialEnabled: boolean = true
  ) {
    this.fillHeight = fillHeight;
    this.boundHeight = boundHeight;
    this.contentPadding = contentPadding;
    this.paddingTop = paddingTop;
    this.paddingBottom = paddingBottom;
    this.materialEnabled = materialEnabled;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    instance.width(CENTERED_DIALOG_WIDTH)
    if (this.fillHeight) {
      instance.height(CENTERED_DIALOG_TALL_HEIGHT)
      instance.constraintSize({
        maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP,
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
    if (this.contentPadding) {
      instance.padding({
        left: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        right: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        top: this.paddingTop,
        bottom: this.paddingBottom
      })
    }
    if (this.materialEnabled) {
      applyCommonSystemMaterial(instance, createCenteredDialogMaterial());
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
// CustomDialog content uses the controller's systemMaterial so the system owns one glass surface.
export const CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true, CENTERED_DIALOG_TOP_PADDING_VP, CENTERED_DIALOG_BOTTOM_PADDING_VP, false);
export const CENTERED_DIALOG_SYSTEM_COMPACT_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true, 16, 12, false);
export const CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true, false, false, CENTERED_DIALOG_TOP_PADDING_VP, CENTERED_DIALOG_BOTTOM_PADDING_VP, false);
export const CENTERED_DIALOG_SYSTEM_TALL_PADDED_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true, false, true, CENTERED_DIALOG_TOP_PADDING_VP, CENTERED_DIALOG_BOTTOM_PADDING_VP, false);
export const CENTERED_DIALOG_SYSTEM_SCROLL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, true, false, CENTERED_DIALOG_TOP_PADDING_VP, CENTERED_DIALOG_BOTTOM_PADDING_VP, false);

@Component
export struct CenteredDialogSurface {
  @Prop fillHeight: boolean = false;
  @Prop materialEnabled: boolean = true;
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
    .attributeModifier(new CenteredDialogSurfaceModifier(
      false,
      false,
      true,
      CENTERED_DIALOG_TOP_PADDING_VP,
      CENTERED_DIALOG_BOTTOM_PADDING_VP,
      this.materialEnabled
    ))
  }

  @Builder
  private buildTallSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .attributeModifier(new CenteredDialogSurfaceModifier(
      true,
      false,
      false,
      CENTERED_DIALOG_TOP_PADDING_VP,
      CENTERED_DIALOG_BOTTOM_PADDING_VP,
      this.materialEnabled
    ))
  }

  @Builder
  private emptyContent() {
  }
}
