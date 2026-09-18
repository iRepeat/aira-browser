import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceCoordinator
} from '../browser/BrowserTransientSurfaceCoordinator';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { RenewalReminderRepository } from '../../data/membership/RenewalReminderRepository';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { FeatureGateCoordinator } from './FeatureGateCoordinator';

export interface RenewalReminderShellFacts {
  appVisible: boolean;
  homeVisible: boolean;
  privacyMode: string;
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

export interface RenewalReminderShell {
  resolveFacts: () => RenewalReminderShellFacts;
}

const RENEWAL_REMINDER_EVALUATION_DELAY_MS: number = 1400;

/**
 * Decides when to tell a lapsed member, unprompted, that their Pro period ended.
 *
 * This owns only the unprompted reminder. It reuses the feature-gate surface so
 * the user sees one renewal sheet regardless of how they arrived at it, and it
 * never suppresses a gate the user triggered by touching a Pro feature: that
 * path is a direct request and must always be honored.
 *
 * Do-not-disturb is keyed by the expiry instant rather than by a plain "shown"
 * flag, so a lapse is announced once but a later period that lapses again is
 * announced again. The record is written only after the sheet actually reveals,
 * because a custom bottom surface mounts asynchronously and an abandoned request
 * must not consume the one-time reminder.
 */
export class RenewalReminderCoordinator {
  private readonly membershipFeature: MembershipFeature;
  private readonly repository: RenewalReminderRepository;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly featureGateCoordinator: FeatureGateCoordinator;
  private readonly shell: RenewalReminderShell;
  private evaluateTimer: number = -1;
  private evaluationGeneration: number = 0;
  private awaitingReveal: boolean = false;

  constructor(
    membershipFeature: MembershipFeature,
    repository: RenewalReminderRepository,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    featureGateCoordinator: FeatureGateCoordinator,
    shell: RenewalReminderShell
  ) {
    this.membershipFeature = membershipFeature;
    this.repository = repository;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.featureGateCoordinator = featureGateCoordinator;
    this.shell = shell;
  }

  scheduleEvaluation(): void {
    this.cancelEvaluation();
    const generation = this.evaluationGeneration;
    this.evaluateTimer = setTimeout((): void => {
      this.evaluateTimer = -1;
      void this.evaluate(generation);
    }, RENEWAL_REMINDER_EVALUATION_DELAY_MS);
  }

  handleShellReset(): void {
    this.cancelEvaluation();
    this.awaitingReveal = false;
  }

  /**
   * Called when the gate surface is dismissed. The reminder is spent on reveal,
   * so nothing is recorded here; this only stops waiting for a reveal that can
   * no longer arrive.
   */
  handleSurfaceDismissed(): void {
    this.awaitingReveal = false;
  }

  /**
   * Records the reminder once its sheet is actually on screen. Guarded by
   * `awaitingReveal` so a gate the user opened by touching a Pro feature is not
   * mistaken for this reminder.
   */
  handleSurfaceRevealed(): void {
    if (!this.awaitingReveal) {
      return;
    }
    this.awaitingReveal = false;
    const lapsed = this.membershipFeature.getLapsedProState();
    if (lapsed.expiredAt <= 0) {
      return;
    }
    void this.repository.markReminded(lapsed.uid, lapsed.expiredAt).catch((_error: Error): void => {
    });
  }

  private cancelEvaluation(): void {
    this.evaluationGeneration += 1;
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private async evaluate(generation: number): Promise<void> {
    if (generation !== this.evaluationGeneration) {
      return;
    }
    if (!this.isDistributionEligible() || !this.canPresent()) {
      return;
    }
    await this.membershipFeature.refreshState({ force: true, loadSyncConfig: true })
      .catch((_error: Error): void => {
      });
    if (generation !== this.evaluationGeneration || !this.canPresent()) {
      return;
    }
    const lapsed = this.membershipFeature.getLapsedProState();
    if (lapsed.uid.length === 0 || lapsed.expiredAt <= 0) {
      return;
    }
    // The service reports a lapsed period only while the account is not Pro, so
    // a restored membership never reaches here. Re-check anyway: a purchase that
    // completed during the refresh must not be followed by "you expired".
    if (this.membershipFeature.getState().plan === 'pro') {
      return;
    }
    await this.repository.initialize().catch((_error: Error): void => {
    });
    if (this.repository.getRecord(lapsed.uid).remindedForExpiredAt >= lapsed.expiredAt) {
      return;
    }
    if (!this.canPresent()) {
      return;
    }
    this.awaitingReveal = true;
    if (!this.featureGateCoordinator.presentRenewalReminder()) {
      this.awaitingReveal = false;
    }
  }

  private canPresent(): boolean {
    if (!this.isDistributionEligible()) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    if (!facts.appVisible || !facts.homeVisible || facts.privacyMode === 'private') {
      return false;
    }
    return !this.transientSurfaceCoordinator.isReleaseNoticeBlocked(facts.promptBlockingFacts);
  }

  private isDistributionEligible(): boolean {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
  }
}
