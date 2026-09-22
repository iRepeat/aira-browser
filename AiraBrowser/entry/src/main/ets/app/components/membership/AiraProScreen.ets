import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import {
  AiraProOverviewViewModel,
  AiraProOverviewViewState
} from '../../../core/membership/AiraProOverviewViewModel';
import { AiraProComplimentaryClaimDialog } from './AiraProComplimentaryClaimDialog';
import { AiraProOverviewScreen } from './AiraProOverviewScreen';
import { CENTERED_DIALOG_CORNER_RADIUS_VP } from '../common/CenteredDialogSurface';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { HuaweiLoginSheetContent } from '../account/HuaweiLoginSheetContent';
import { SyncDesktopBookmarkGuideContent } from '../sync/SyncDesktopBookmarkGuideContent';
import {
  SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE
} from '../../../services/sync/SyncDesktopBookmarkGuideMarkdownService';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import { AiraLegalWebDocumentContent } from '../legal/AiraLegalWebDocumentContent';
import {
  AiraLegalDocumentId,
  AiraLegalDocumentLink,
  resolveAiraLegalDocumentLink
} from '../../../services/legal/AiraLegalDocuments';
import {
  AiraProPurchaseCoordinator,
  AiraProPurchaseFlowHostAdapter
} from '../../../core/membership/AiraProPurchaseCoordinator';
import { SyncSettingsRefreshSignal } from '../../../core/sync/SyncSettingsRefreshSignal';
import {
  sharedAiraSyncConfigStore,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { AiraComplimentaryClaimResult } from '../../../features/membership/MembershipFeature';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS } from '../../../services/membership/MembershipRefreshPolicyService';

type AiraProSheetKind = 'none' | 'login' | 'legalDocument' | 'selfHostingGuide';
export type AiraProPresentationMode = 'page' | 'workspace';
export type AiraProPageLayoutMode = 'phone' | 'large_screen';

const AIRA_PRO_PAGE_CONTENT_MAX_WIDTH_VP: number = 760;
const AIRA_PRO_DESKTOP_DIALOG_MIN_WIDTH_VP: number = 520;
const AIRA_PRO_DESKTOP_DIALOG_MAX_WIDTH_VP: number = 720;
const AIRA_PRO_DESKTOP_DIALOG_MIN_HEIGHT_VP: number = 420;
const AIRA_PRO_DESKTOP_DIALOG_MAX_HEIGHT_VP: number = 720;

@Component
export struct AiraProScreen {
  @Prop presentationMode: AiraProPresentationMode = 'page';
  @Prop pageLayoutMode: AiraProPageLayoutMode = 'phone';
  @Prop embeddedDataScope: string = '';
  @Prop embeddedPrivacyMode: string = '';
  @Prop embeddedBoundarySource: string = '';
  onRequestClose: () => void = () => {};
  private viewModel: AiraProOverviewViewModel = new AiraProOverviewViewModel();
  private purchaseCoordinator: AiraProPurchaseCoordinator = new AiraProPurchaseCoordinator(sharedMembershipFeature);
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private purchaseFlowHost: AiraProPurchaseFlowHostAdapter = new AiraProPurchaseFlowHostAdapter(
    () => {
      this.applyAiraProState();
      this.syncSettingsRefreshSignal.bump();
    },
    () => {
      this.ensureHuaweiAccountSignedIn();
    },
    (message: string) => {
      this.showToast(message);
    }
  );
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential
      ) => {
        this.handleHuaweiLoginPanelResult(error, response);
      });
  private contentScroller: Scroller = new Scroller();
  private themePreferencesListenerKey: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private state: AiraProOverviewViewState = this.viewModel.buildState(
    sharedMembershipFeature.getState(),
    this.dataScope,
    this.privacyMode
  );
  private complimentaryClaimInFlight: boolean = false;
  private complimentaryClaimDialogController: CustomDialogController = new CustomDialogController({
    builder: AiraProComplimentaryClaimDialog({
      state: $state,
      onClaim: (): void => {
        this.claimComplimentaryMembership();
      }
    }),
    customStyle: true,
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  @State private activeSheetVisible: boolean = false;
  @State private activeSheetMounted: boolean = false;
  @State private activeSheetKind: AiraProSheetKind = 'none';
  @State private legalDocument: AiraLegalDocumentLink =
    resolveAiraLegalDocumentLink('user_service_agreement');
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('handleStoredThemeChanged')
  private storedResolvedThemeMode: string = 'light';

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
    if (this.isDesktopPresentation()) {
      this.purchaseCoordinator.handlePageShow(this.purchaseFlowHost, this.buildAiraProDataBoundaryInput());
    }
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
    try {
      this.complimentaryClaimDialogController.close();
    } catch (_error) {
    }
  }

  onPageShow(): void {
    this.refreshState();
    this.purchaseCoordinator.handlePageShow(this.purchaseFlowHost, this.buildAiraProDataBoundaryInput());
  }

  build() {
    if (this.isDesktopPresentation()) {
      this.buildDesktopSurface()
    } else {
      this.buildPageSurface()
    }
  }

  @Builder
  private buildPageSurface() {
    Column() {
      SettingsHdsScaffold({
        title: this.state.title,
        backIconKind: 'close',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.controlBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        menuActionText: this.resolveRestorePurchaseActionLabel(),
        scrollers: [this.contentScroller],
        contentKind: 'standard',
        onBack: () => {
          this.navigationCoordinator.back();
        },
        onMenuAction: () => {
          this.restorePurchase();
        }
      }) {
        this.buildAiraProContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.activeSheetVisible, this.buildActiveSheet(), {
      preferType: this.pageLayoutMode === 'large_screen' ? SheetType.CENTER : SheetType.BOTTOM,
      height: this.resolveActiveSheetHeight(),
      dragBar: this.pageLayoutMode !== 'large_screen',
      showClose: this.activeSheetKind === 'login',
      backgroundColor: this.resolveActiveSheetBackgroundColor(),
      onDisappear: () => {
        this.handleActiveSheetDisappear();
      }
    })
  }

  @Builder
  private buildDesktopSurface() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Column() {
          this.buildAiraProContent()
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: this.resolveDesktopContentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

      if (this.activeSheetMounted) {
        BrowserAdaptiveModalOverlay({
          visible: this.activeSheetVisible,
          layoutMode: 'large_screen',
          title: this.resolveDesktopDialogTitle(),
          showDesktopHeader: this.shouldShowDesktopDialogHeader(),
          desktopWidth: '76%',
          desktopHeight: this.resolveDesktopDialogHeight(),
          desktopMinWidth: AIRA_PRO_DESKTOP_DIALOG_MIN_WIDTH_VP,
          desktopMaxWidth: AIRA_PRO_DESKTOP_DIALOG_MAX_WIDTH_VP,
          desktopMinHeight: AIRA_PRO_DESKTOP_DIALOG_MIN_HEIGHT_VP,
          desktopMaxHeight: AIRA_PRO_DESKTOP_DIALOG_MAX_HEIGHT_VP,
          onDismiss: () => {
            this.handleActiveSheetDisappear();
          }
        }) {
          this.buildActiveSheet()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }

  @Builder
  private buildAiraProContent() {
    AiraProOverviewScreen({
      state: this.state,
      surfaceBackground: this.theme.surfaceBackground,
      controlBackground: this.theme.controlBackground,
      accentColor: this.theme.accent,
      onAccentColor: this.theme.onAccent,
      primaryTextColor: this.theme.textPrimary,
      secondaryTextColor: this.theme.textSecondary,
      dividerColor: this.theme.divider,
      settingsIconForeground: this.theme.settingsIconForeground,
      settingsIconBackgrounds: this.theme.settingsIconBackgrounds,
      syncProviderIconBackgrounds: this.theme.syncProviderIconBackgrounds,
      scroller: this.contentScroller,
      onSubscribe: (planId: string) => {
        this.openProPurchase(planId);
      },
      onOpenSelfHostingGuide: () => {
        this.openSelfHostingGuide();
      },
      onOpenMembershipTerms: () => {
        this.openMembershipTerms();
      },
      onOpenAutoRenewalNotice: () => {
        this.openAutoRenewalNotice();
      },
      onManageSubscription: () => {
        this.openSubscriptionManagement();
      },
      onOpenComplimentaryClaim: () => {
        this.openComplimentaryClaim();
      }
    })
  }

  /**
   * The page's only title-bar action. “恢复购买” is low frequency but must stay
   * findable, so it sits opposite the close action instead of in a footer link
   * the user has to scroll to. It is hidden when there is nothing to restore.
   */
  private resolveRestorePurchaseActionLabel(): string {
    if (!this.state.proActionsEnabled) {
      return '';
    }
    return this.state.plans.length > 0 ? '恢复购买' : '';
  }

  private restorePurchase(): void {
    const selectedPlan = this.state.plans.length > 0 ? this.state.plans[0].id : 'monthly';
    this.restorePurchaseForPlan(selectedPlan);
  }

  private resolveDesktopContentMaxWidth(): Length {
    return this.presentationMode === 'workspace' ? '100%' : AIRA_PRO_PAGE_CONTENT_MAX_WIDTH_VP;
  }

  @Builder
  private buildActiveSheet() {
    if (this.activeSheetKind === 'legalDocument') {
      AiraLegalWebDocumentContent({
        documentUrl: this.legalDocument.url,
        styleId: 'aira-pro-legal-document-style'
      })
        .width('100%')
        .height('100%')
    } else if (this.activeSheetKind === 'selfHostingGuide') {
      SyncDesktopBookmarkGuideContent()
        .width('100%')
        .height('100%')
    } else {
      this.buildHuaweiLoginSheet()
    }
  }

  private openComplimentaryClaim(): void {
    if (!this.state.complimentaryClaim.entryVisible) {
      return;
    }
    this.complimentaryClaimDialogController.open();
  }

  /**
   * The centered dialog only starts the claim. The hosted service decides
   * whether this account receives the 15 days and returns the grant to store.
   */
  private claimComplimentaryMembership(): void {
    if (!this.state.complimentaryClaim.actionEnabled || this.complimentaryClaimInFlight) {
      return;
    }
    this.complimentaryClaimInFlight = true;
    sharedMembershipFeature.claimComplimentaryMembership(this.buildAiraProDataBoundaryInput())
      .then((result: AiraComplimentaryClaimResult) => {
        this.complimentaryClaimInFlight = false;
        if (result.ok) {
          this.complimentaryClaimDialogController.close();
        }
        this.applyAiraProState();
        this.showToast(result.message.length > 0 ? result.message : '会员领取失败，请稍后再试。');
        if (result.ok) {
          sharedMembershipFeature.refreshStateForBoundary(this.buildAiraProDataBoundaryInput(), { force: true })
            .then(() => {
              this.applyAiraProState();
            })
            .catch((_error: Error) => {
              this.applyAiraProState();
            });
        }
      })
      .catch((_error: Error) => {
        this.complimentaryClaimInFlight = false;
        this.showToast('会员领取失败，请稍后再试。');
      });
  }

  @Builder
  private buildHuaweiLoginSheet() {
    HuaweiLoginSheetContent({
      controller: this.huaweiLoginButtonController,
      onOpenUserAgreement: () => {
        this.openHuaweiLoginUserAgreement();
      },
      onOpenPrivacyPolicy: () => {
        this.openHuaweiLoginPrivacyPolicy();
      }
    })
  }

  private refreshState(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      if (this.isDesktopPresentation()) {
        this.onRequestClose();
      } else {
        this.navigationCoordinator.back();
      }
      return;
    }
    const boundaryState = this.isDesktopPresentation()
      ? readBrowserBoundaryRouteState({
        dataScope: this.embeddedDataScope,
        privacyMode: this.embeddedPrivacyMode,
        boundarySource: this.embeddedBoundarySource
      })
      : readBrowserBoundaryRouteState({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshThemeState();
    this.applyAiraProState();
    sharedMembershipFeature.refreshStateForBoundary(this.buildAiraProDataBoundaryInput(), {
      minFreshMs: MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS
    })
      .then(() => {
        this.applyAiraProState();
      })
      .catch((_error: Error) => {
        this.applyAiraProState();
      });
  }

  private applyAiraProState(): void {
    this.state = this.viewModel.buildState(
      sharedMembershipFeature.getState(),
      this.dataScope,
      this.privacyMode
    );
  }

  private openProPurchase(planId: string = 'monthly'): void {
    this.purchaseCoordinator.startPurchaseFlow(
      getContext(this) as common.UIAbilityContext,
      planId,
      this.getHuaweiUid(),
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    );
  }

  /**
   * The active-member card's single action. An active subscription has exactly
   * one thing left to do — open Huawei's subscription management — so the
   * page goes straight there instead of routing through a confirmation dialog
   * that only had one real outcome.
   */
  private openSubscriptionManagement(): void {
    this.purchaseCoordinator.openLifetimeUpgradeSubscriptionManagement(
      getContext(this) as common.UIAbilityContext,
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    );
  }

  /**
   * The free-route row's only action. Cold self-hosting has nothing to configure
   * on this page, so it hands off to the existing deployment guide instead of a
   * second copy of the recipe. The desktop workspace keeps its own scroll host,
   * so it reuses the same guide as an in-workspace sheet rather than pushing a
   * page route behind the workspace scaffold.
   */
  private openSelfHostingGuide(): void {
    if (this.isDesktopPresentation()) {
      this.openActiveSheet('selfHostingGuide');
      return;
    }
    this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.buildAiraProBoundaryState());
  }

  private restorePurchaseForPlan(planId: string): void {
    this.purchaseCoordinator.restorePurchaseFlow(
      getContext(this) as common.UIAbilityContext,
      this.getHuaweiUid(),
      planId,
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    );
  }

  private openMembershipTerms(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('pro_membership_service_agreement');
      return;
    }
    this.navigationCoordinator.openLegalWebDocument(
      'pro_membership_service_agreement',
      this.buildAiraProBoundaryState()
    );
  }

  private openAutoRenewalNotice(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('pro_auto_renewal_service_agreement');
      return;
    }
    this.navigationCoordinator.openLegalWebDocument(
      'pro_auto_renewal_service_agreement',
      this.buildAiraProBoundaryState()
    );
  }

  private openHuaweiLoginUserAgreement(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('user_service_agreement');
      return;
    }
    this.closeActiveSheet();
    this.navigationCoordinator.openLegalWebDocument(
      'user_service_agreement',
      this.buildAiraProBoundaryState()
    );
  }

  private openHuaweiLoginPrivacyPolicy(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('privacy_statement');
      return;
    }
    this.closeActiveSheet();
    this.navigationCoordinator.openPrivacyStatement(this.buildAiraProBoundaryState());
  }

  private openDesktopLegalDocument(documentId: AiraLegalDocumentId): void {
    this.legalDocument = resolveAiraLegalDocumentLink(documentId);
    this.openActiveSheet('legalDocument');
  }

  private buildAiraProBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: 'aira_pro'
    };
  }

  private buildAiraProDataBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private isDesktopPresentation(): boolean {
    return this.presentationMode === 'workspace';
  }

  private getHuaweiUid(): string {
    return sharedAiraSyncConfigStore.getSettings().huaweiCloud.uid.trim();
  }

  private ensureHuaweiAccountSignedIn(): boolean {
    if (this.getHuaweiUid().length > 0) {
      return true;
    }
    if (!sharedHuaweiAccountMutationCoordinator.canSignIn(this.buildAiraProDataBoundaryInput())) {
      this.showToast('请回到普通会话后登录华为账号。');
      return false;
    }
    this.showToast('请先使用华为账号登录后再开通 Aira Pro 权益。');
    this.openActiveSheet('login');
    return false;
  }

  private handleHuaweiLoginPanelResult(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential
  ): void {
    if (error !== undefined) {
      if (error.code !== 1001502012) {
        this.showToast(error.message.length > 0 ? error.message : '华为账号登录失败');
      }
      return;
    }
    if (response.authorizationCode.trim().length <= 0 && response.openID.trim().length <= 0) {
      this.showToast('华为账号登录未完成');
      return;
    }
    this.closeActiveSheet();
    this.signInHuaweiAccount();
  }

  private openActiveSheet(kind: AiraProSheetKind): void {
    this.activeSheetKind = kind;
    this.activeSheetMounted = true;
    this.activeSheetVisible = true;
  }

  private closeActiveSheet(): void {
    this.activeSheetVisible = false;
    this.activeSheetMounted = false;
    this.activeSheetKind = 'none';
  }

  private handleActiveSheetDisappear(): void {
    this.activeSheetVisible = false;
    this.activeSheetMounted = false;
    this.activeSheetKind = 'none';
  }

  private resolveActiveSheetHeight(): SheetSize {
    return SheetSize.FIT_CONTENT;
  }

  private resolveActiveSheetBackgroundColor(): ResourceColor {
    return this.storedFloatingSurfaceColor;
  }

  private resolveDesktopDialogTitle(): string {
    if (this.activeSheetKind === 'login') {
      return '登录华为账号';
    }
    if (this.activeSheetKind === 'selfHostingGuide') {
      return SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE;
    }
    if (this.activeSheetKind === 'legalDocument') {
      return this.legalDocument.title;
    }
    return '进入 Aira Pro';
  }

  private shouldShowDesktopDialogHeader(): boolean {
    return this.activeSheetKind === 'login' ||
      this.activeSheetKind === 'legalDocument' ||
      this.activeSheetKind === 'selfHostingGuide';
  }

  private resolveDesktopDialogHeight(): Length {
    if (this.activeSheetKind === 'legalDocument' || this.activeSheetKind === 'selfHostingGuide') {
      return '82%';
    }
    return 500;
  }

  private signInHuaweiAccount(): void {
    sharedHuaweiAccountMutationCoordinator.signIn(this.buildAiraProDataBoundaryInput())
      .then((result) => {
        if (result.type === 'failed') {
          this.showToast(result.message.length > 0 ? result.message : result.title);
          return;
        }
        this.syncSettingsRefreshSignal.bump();
        this.refreshState();
        this.showToast(result.title);
      })
      .catch((_error: Error) => {
        this.showToast('华为账号登录失败');
      });
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private handleStoredThemeChanged(): void {
    this.refreshThemeState();
    this.applyAiraProState();
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeState();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

}
