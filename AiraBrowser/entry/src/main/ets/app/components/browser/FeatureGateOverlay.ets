import {
  createHiddenFeatureGateSnapshot,
  FeatureGateAction,
  FeatureGateSnapshot
} from '../../../core/membership/FeatureGateCoordinator';
import { FeatureGateSheet } from '../membership/FeatureGateSheet';
import { BrowserAdaptiveModalOverlay } from './BrowserAdaptiveModalOverlay';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
  FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y
} from './BrowserShellPresentationTokens';

@Component
export struct FeatureGateOverlay {
  @Prop visible: boolean = false;
  @Prop state: FeatureGateSnapshot = createHiddenFeatureGateSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: FeatureGateAction) => void = (_action: FeatureGateAction) => {};
  onSelectPlan: (planId: string) => void = (_planId: string) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      title: this.state.title,
      phoneEnterOffsetY: FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      desktopWidth: '70%',
      desktopHeight: 520,
      desktopMinWidth: 480,
      desktopMaxWidth: 560,
      desktopMinHeight: 460,
      desktopMaxHeight: 600,
      onDismiss: () => {
        this.onAction('dismiss');
      }
    }) {
      FeatureGateSheet({
        state: this.state,
        layoutMode: this.layoutMode,
        onAction: (action: FeatureGateAction) => {
          this.onAction(action);
        },
        onSelectPlan: (planId: string): void => {
          this.onSelectPlan(planId);
        }
      })
    }
  }
}
