import {
  createHiddenNewUserGiftSnapshot,
  NewUserGiftAction,
  NewUserGiftSnapshot
} from '../../../core/membership/NewUserGiftCoordinator';
import { NewUserGiftSheet } from '../membership/NewUserGiftSheet';
import { BrowserAdaptiveModalOverlay } from './BrowserAdaptiveModalOverlay';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
  FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y
} from './BrowserShellPresentationTokens';

const NEW_USER_GIFT_OVERLAY_TITLE: string = '新用户礼包';

@Component
export struct NewUserGiftOverlay {
  @Prop visible: boolean = false;
  @Prop state: NewUserGiftSnapshot = createHiddenNewUserGiftSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: NewUserGiftAction) => void = (_action: NewUserGiftAction) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      title: NEW_USER_GIFT_OVERLAY_TITLE,
      // The gift is announced once per account. An outside tap must not be what dismisses it,
      // or the user loses the notification without ever reading what was granted.
      dismissOnOutsideTap: false,
      phoneEnterOffsetY: FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
      phoneSheetAlignment: Alignment.Center,
      animationDurationMs: FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      tier: 's',
      onDismiss: () => {
        this.onAction('dismiss');
      }
    }) {
      NewUserGiftSheet({
        state: this.state,
        layoutMode: this.layoutMode,
        onAction: (action: NewUserGiftAction) => {
          this.onAction(action);
        }
      })
    }
  }
}
