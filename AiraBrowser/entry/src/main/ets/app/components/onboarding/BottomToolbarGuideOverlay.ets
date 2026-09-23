import {
  createHiddenBottomToolbarGuideSnapshot,
  BottomToolbarGuideAction,
  BottomToolbarGuideSnapshot
} from '../../../core/onboarding/BottomToolbarGuideCoordinator';
import { BottomToolbarGuideSheet } from './BottomToolbarGuideSheet';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
  FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y
} from '../browser/BrowserShellPresentationTokens';

const BOTTOM_TOOLBAR_GUIDE_OVERLAY_TITLE: string = '底部工具条提示';

/**
 * The one-time lesson about the swipe-down toolbar gesture. It is anchored in the
 * middle of the viewport like the welcome-gift announcement.
 */
@Component
export struct BottomToolbarGuideOverlay {
  @Prop visible: boolean = false;
  @Prop state: BottomToolbarGuideSnapshot = createHiddenBottomToolbarGuideSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: BottomToolbarGuideAction) => void = (_action: BottomToolbarGuideAction) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      title: BOTTOM_TOOLBAR_GUIDE_OVERLAY_TITLE,
      // The lesson is taught once per device. A tap on the scrim must not be what ends it,
      // or an accidental tap swallows the only time the gesture is explained.
      dismissOnOutsideTap: false,
      phoneEnterOffsetY: FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
      phoneSheetAlignment: Alignment.Center,
      animationDurationMs: FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      tier: 's',
      onDismiss: () => {
        this.onAction('acknowledge');
      }
    }) {
      BottomToolbarGuideSheet({
        state: this.state,
        layoutMode: this.layoutMode,
        onAction: (action: BottomToolbarGuideAction) => {
          this.onAction(action);
        }
      })
    }
  }
}
