import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceCoordinator
} from '../browser/BrowserTransientSurfaceCoordinator';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { NewUserGiftRepository } from '../../data/membership/NewUserGiftRepository';
import { AiraNewUserGiftView } from '../../common/models/MembershipModels';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type NewUserGiftAction = 'dismiss';

export interface NewUserGiftSnapshot {
  visible: boolean;
  uid: string;
  title: string;
  message: string;
  grantDays: number;
  actionTitle: string;
}

export function createHiddenNewUserGiftSnapshot(): NewUserGiftSnapshot {
  return {
    visible: false,
    uid: '',
    title: '',
    message: '',
    grantDays: 0,
    actionTitle: ''
  };
}

export interface NewUserGiftShellFacts {
  dataScope: string;
  privacyMode: string;
  appVisible: boolean;
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

export interface NewUserGiftShell {
  resolveFacts: () => NewUserGiftShellFacts;
  publishState: (snapshot: NewUserGiftSnapshot) => void;
  showToast: (message: string) => void;
}

const NEW_USER_GIFT_DEFAULT_GRANT_DAYS: number = 30;
const NEW_USER_GIFT_EVALUATION_DELAY_MS: number = 900;
// A previously fetched descriptor is reused for this long before another
// authoritative membership read is spent on it.
const NEW_USER_GIFT_DESCRIPTOR_FRESH_MS: number = 10 * 60 * 1000;

/**
 * Announces the welcome gift a new account already receives. The hosted
 * service applies the month of Aira Pro on its own, so this owner never gates
 * the grant on a user action: it best-effort nudges the idempotent grant,
 * shows a one-time notice, and reports what the service did. Losing the
 * notice never loses the entitlement.
 */
export class NewUserGiftCoordinator {
  private readonly membershipFeature: MembershipFeature;
  private readonly repository: NewUserGiftRepository;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly shell: NewUserGiftShell;
  private evaluateTimer: number = -1;
  private evaluationGeneration: number = 0;
  private snapshot: NewUserGiftSnapshot = createHiddenNewUserGiftSnapshot();
  private ensureInFlight: boolean = false;

  constructor(
    membershipFeature: MembershipFeature,
    repository: NewUserGiftRepository,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    shell: NewUserGiftShell
  ) {
    this.membershipFeature = membershipFeature;
    this.repository = repository;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.shell = shell;
  }

  getSnapshot(): NewUserGiftSnapshot {
    return this.snapshot;
  }

  scheduleEvaluation(): void {
    this.cancelEvaluation();
    const generation = this.evaluationGeneration;
    this.evaluateTimer = setTimeout((): void => {
      this.evaluateTimer = -1;
      void this.evaluate(generation);
    }, NEW_USER_GIFT_EVALUATION_DELAY_MS);
  }

  handleAction(_action: NewUserGiftAction): void {
    this.transientSurfaceCoordinator.dismiss('new_user_gift');
  }

  handleSurfaceDismissed(): void {
    this.publishState(createHiddenNewUserGiftSnapshot());
  }

  handleShellReset(): void {
    this.cancelEvaluation();
    this.publishState(createHiddenNewUserGiftSnapshot());
  }

  private cancelEvaluation(): void {
    this.evaluationGeneration += 1;
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private async evaluate(generation: number): Promise<void> {
    if (generation !== this.evaluationGeneration || this.snapshot.visible) {
      return;
    }
    if (!this.isDistributionEligible()) {
      return;
    }
    let gift = await this.resolveGiftState();
    if (!this.isNewUser(gift)) {
      return;
    }
    if (gift.grantedAt <= 0) {
      gift = await this.ensureGrant(gift);
      if (!this.isNewUser(gift)) {
        return;
      }
    }
    // Only announce a grant that actually landed; otherwise the notice would
    // claim a month of Pro the account does not have yet.
    if (!this.hasGrantLanded(gift)) {
      return;
    }
    if (!this.canPresent(generation)) {
      return;
    }
    await this.repository.initialize().catch((_error: Error): void => {
    });
    if (!this.canPresent(generation)) {
      return;
    }
    if (this.repository.getRecord(gift.uid).acknowledgedAt > 0) {
      return;
    }
    this.publishState(this.buildVisibleSnapshot(gift));
    this.transientSurfaceCoordinator.present({
      id: 'new_user_gift',
      revealDelayMs: 0,
      dismissDurationMs: 0,
      shouldReveal: (): boolean => this.canPresent(generation)
    });
    await this.repository.markAcknowledged(gift.uid).catch((_error: Error): void => {
    });
  }

  /**
   * Best-effort idempotent nudge so an eligible account's grant exists even if
   * the service only issues it on an authenticated read. A private session is
   * refused by the privacy policy and simply skips the nudge; the server-side
   * grant is unaffected.
   */
  private async ensureGrant(gift: AiraNewUserGiftView): Promise<AiraNewUserGiftView> {
    if (this.ensureInFlight) {
      return gift;
    }
    const facts = this.shell.resolveFacts();
    if (facts.privacyMode === 'private') {
      return gift;
    }
    this.ensureInFlight = true;
    try {
      const result = await this.membershipFeature.ensureNewUserGift({
        dataScope: facts.dataScope,
        privacyMode: facts.privacyMode
      });
      if (!result.ok && result.code !== 'grant_not_applied') {
        return gift;
      }
    } catch (_error) {
      return gift;
    } finally {
      this.ensureInFlight = false;
    }
    return this.membershipFeature.getNewUserGiftState();
  }

  /**
   * Reads the server-owned gift descriptor, spending one authoritative
   * membership refresh when the cached descriptor is missing or stale for the
   * resolved account.
   */
  private async resolveGiftState(): Promise<AiraNewUserGiftView> {
    const cached = this.membershipFeature.getNewUserGiftState();
    if (cached.uid.length > 0 && cached.fetchedAt > 0 &&
      Date.now() - cached.fetchedAt < NEW_USER_GIFT_DESCRIPTOR_FRESH_MS) {
      return cached;
    }
    if (this.membershipFeature.getState().userId === 'local') {
      return cached;
    }
    await this.membershipFeature.refreshState({ force: true, loadSyncConfig: true })
      .catch((_error: Error): void => {
      });
    return this.membershipFeature.getNewUserGiftState();
  }

  private canPresent(generation: number): boolean {
    if (generation !== this.evaluationGeneration || this.snapshot.visible) {
      return false;
    }
    if (!this.isDistributionEligible()) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    if (!facts.appVisible || facts.privacyMode === 'private') {
      return false;
    }
    return !this.transientSurfaceCoordinator.isReleaseNoticeBlocked(facts.promptBlockingFacts);
  }

  private isNewUser(gift: AiraNewUserGiftView): boolean {
    return this.isDistributionEligible() && gift.uid.length > 0 && gift.eligible;
  }

  private hasGrantLanded(gift: AiraNewUserGiftView): boolean {
    return gift.grantedAt > 0 && this.membershipFeature.getState().plan === 'pro';
  }

  private isDistributionEligible(): boolean {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
  }

  private buildVisibleSnapshot(gift: AiraNewUserGiftView): NewUserGiftSnapshot {
    const grantDays = gift.grantDays > 0 ? gift.grantDays : NEW_USER_GIFT_DEFAULT_GRANT_DAYS;
    return {
      visible: true,
      uid: gift.uid,
      title: '新用户会员已到账',
      message: `欢迎使用 Aira。你已经获得 ${grantDays} 天 Aira Pro 权益，可在会员页查看。`,
      grantDays: grantDays,
      actionTitle: '知道了'
    };
  }

  private publishState(snapshot: NewUserGiftSnapshot): void {
    this.snapshot = snapshot;
    this.shell.publishState(snapshot);
  }
}
