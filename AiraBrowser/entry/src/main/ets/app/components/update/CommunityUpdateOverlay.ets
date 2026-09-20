import {
  createIdleCommunityUpdateSnapshot,
  CommunityUpdateAction,
  CommunityUpdateCheckSnapshot
} from '../../../core/update/CommunityUpdateCheckCoordinator';
import { CommunityUpdateSheet } from './CommunityUpdateSheet';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
  FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y
} from '../browser/BrowserShellPresentationTokens';

const COMMUNITY_UPDATE_OVERLAY_TITLE: string = '软件更新';

/**
 * Anchors the Community update notice in the middle of the viewport, like the
 * welcome-gift announcement and the toolbar lesson.
 */
@Component
export struct CommunityUpdateOverlay {
  @Prop visible: boolean = false;
  @Prop state: CommunityUpdateCheckSnapshot = createIdleCommunityUpdateSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: CommunityUpdateAction) => void = (_action: CommunityUpdateAction) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      title: COMMUNITY_UPDATE_OVERLAY_TITLE,
      phoneEnterOffsetY: FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
      phoneSheetAlignment: Alignment.Center,
      animationDurationMs: FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      desktopWidth: '70%',
      desktopHeight: 520,
      desktopMinWidth: 480,
      desktopMaxWidth: 560,
      desktopMinHeight: 460,
      desktopMaxHeight: 620,
      onDismiss: () => {
        this.onAction('dismiss');
      }
    }) {
      CommunityUpdateSheet({
        state: this.state,
        layoutMode: this.layoutMode,
        onAction: (action: CommunityUpdateAction) => {
          this.onAction(action);
        }
      })
    }
  }
}
