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
      phoneEnterOffsetY: FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
      phoneSheetAlignment: Alignment.Center,
      animationDurationMs: FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      desktopWidth: '70%',
      desktopHeight: 460,
      desktopMinWidth: 480,
      desktopMaxWidth: 560,
      desktopMinHeight: 420,
      desktopMaxHeight: 520,
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
