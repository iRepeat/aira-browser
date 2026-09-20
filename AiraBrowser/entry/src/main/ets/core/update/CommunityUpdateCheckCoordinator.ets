import {
  CommunityUpdateCheckService
} from '../../services/update/CommunityUpdateCheckService';
import { CommunityReleaseInfo } from '../../services/update/CommunityReleaseFeedService';
import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceId,
  BrowserTransientSurfacePresentationRequest,
  BrowserTransientSurfaceToken
} from '../browser/BrowserTransientSurfaceCoordinator';

export type CommunityUpdateAction = 'dismiss' | 'open_release_page';

export interface CommunityUpdateCheckSnapshot {
  /** Whether a newer Community release is known and may be shown. */
  available: boolean;
  /** A check is running right now. */
  checking: boolean;
  /** A check completed at least once this session. */
  checked: boolean;
  /** The last completed check failed. */
  failed: boolean;
  currentVersionName: string;
  currentVersionCode: number;
  versionName: string;
  versionCode: number;
  title: string;
  summary: string;
  items: string[];
  releaseUrl: string;
  /** One-line outcome for the manual entry point; empty while idle or automatic. */
  statusMessage: string;
}

export function createIdleCommunityUpdateSnapshot(): CommunityUpdateCheckSnapshot {
  return {
    available: false,
    checking: false,
    checked: false,
    failed: false,
    currentVersionName: '',
    currentVersionCode: 0,
    versionName: '',
    versionCode: 0,
    title: '',
    summary: '',
    items: [],
    releaseUrl: '',
    statusMessage: ''
  };
}

export interface CommunityUpdateCheckShellFacts {
  appVisible: boolean;
  privacyMode: string;
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

/**
 * The narrow slice of the transient-surface owner this prompt needs, mirroring the
 * other one-time surfaces so the coordinator cannot reach the whole browser.
 */
export interface CommunityUpdateCheckSurface {
  present: (request: BrowserTransientSurfacePresentationRequest) => BrowserTransientSurfaceToken;
  dismiss: (id: BrowserTransientSurfaceId) => void;
  isReleaseNoticeBlocked: (facts: BrowserTransientPromptBlockingFacts) => boolean;
}

export interface CommunityUpdateCheckShell {
  resolveFacts: () => CommunityUpdateCheckShellFacts;
  publishState: (snapshot: CommunityUpdateCheckSnapshot) => void;
  openReleasePage: (url: string) => void;
  showToast: (message: string) => void;
}

const COMMUNITY_UPDATE_EVALUATION_DELAY_MS: number = 1200;

/**
 * Presents the first-party Community update notice.
 *
 * The Community distribution ships through GitHub Releases, so the browser itself
 * — not an app store — has to tell the user a newer build exists. This owner reads
 * the check result from {@link CommunityUpdateCheckService}, announces a newer
 * release once per version, and opens the matching release page on request.
 *
 * It only points at the release page: the Community package is unsigned and
 * only the user can sign and sideload it.
 */
export class CommunityUpdateCheckCoordinator {
  private readonly service: CommunityUpdateCheckService;
  private readonly surface: CommunityUpdateCheckSurface;
  private readonly shell: CommunityUpdateCheckShell;
  private readonly evaluationDelayMs: number;
  private evaluateTimer: number = -1;
  private evaluationGeneration: number = 0;
  private presentationGeneration: number = 0;
  private snapshot: CommunityUpdateCheckSnapshot = createIdleCommunityUpdateSnapshot();

  constructor(
    service: CommunityUpdateCheckService,
    surface: CommunityUpdateCheckSurface,
    shell: CommunityUpdateCheckShell,
    evaluationDelayMs: number = COMMUNITY_UPDATE_EVALUATION_DELAY_MS
  ) {
    this.service = service;
    this.surface = surface;
    this.shell = shell;
    this.evaluationDelayMs = evaluationDelayMs;
  }

  getSnapshot(): CommunityUpdateCheckSnapshot {
    return this.snapshot;
  }

  /**
   * Decides whether the automatic notice may present now. Safe to call on every
   * home return: an ineligible build, an already-notified release, or a busy lane
   * simply defers the check instead of losing it.
   */
  scheduleEvaluation(): void {
    this.cancelEvaluation();
    if (!this.service.isCommunity()) {
      return;
    }
    const generation = this.evaluationGeneration;
    this.evaluateTimer = setTimeout((): void => {
      this.evaluateTimer = -1;
      void this.evaluate(generation);
    }, this.evaluationDelayMs);
  }

  handleAction(action: CommunityUpdateAction): void {
    if (action === 'open_release_page' && this.snapshot.releaseUrl.length > 0) {
      this.shell.openReleasePage(this.snapshot.releaseUrl);
    }
    this.surface.dismiss('community_update');
  }

  /**
   * Records that the notice reached the user. A custom bottom surface mounts
   * asynchronously, so an abandoned presentation must not consume the one-time
   * announcement for that release.
   */
  handleSurfaceRevealed(): void {
    if (!this.snapshot.available || this.snapshot.versionCode <= 0) {
      return;
    }
    void this.service.markNotified(this.snapshot.versionCode);
  }

  handleSurfaceDismissed(): void {
    this.presentationGeneration += 1;
    this.publish(this.withAvailability(false));
  }

  handleShellReset(): void {
    this.cancelEvaluation();
    this.presentationGeneration += 1;
    this.publish(this.withAvailability(false));
  }

  private cancelEvaluation(): void {
    this.evaluationGeneration += 1;
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private async evaluate(generation: number): Promise<void> {
    if (generation !== this.evaluationGeneration || this.snapshot.available) {
      return;
    }
    if (!this.canPresent(generation)) {
      return;
    }
    const result = await this.service.check();
    if (generation !== this.evaluationGeneration || result.outcome !== 'update_available') {
      return;
    }
    // The lane can be taken while the feed is in flight; re-check before presenting.
    if (!this.canPresent(generation) || result.release === undefined) {
      return;
    }
    this.presentNotice(result.release);
  }

  private presentNotice(release: CommunityReleaseInfo): void {
    // A release that carries no versionCode cannot be remembered as notified, so
    // the notice would repeat forever; fall back to a quiet toast instead.
    if (release.versionCode <= 0) {
      this.shell.showToast(`发现新版本 ${release.versionName}`);
      return;
    }
    const stored = this.service.getRepositoryState();
    if (stored.lastNotifiedVersionCode >= release.versionCode) {
      return;
    }
    const current = this.service.resolveCurrentVersion();
    this.publish({
      available: true,
      checking: false,
      checked: true,
      failed: false,
      currentVersionName: current.versionName,
      currentVersionCode: current.versionCode,
      versionName: release.versionName,
      versionCode: release.versionCode,
      title: release.title,
      summary: release.summary,
      items: release.items,
      releaseUrl: release.releaseUrl,
      statusMessage: ''
    });
    this.presentationGeneration += 1;
    const presentationGeneration = this.presentationGeneration;
    this.surface.present({
      id: 'community_update',
      revealDelayMs: 0,
      dismissDurationMs: 0,
      shouldReveal: (): boolean =>
        presentationGeneration === this.presentationGeneration && this.snapshot.available
    });
  }

  /**
   * Whether a presentation may still start. `snapshot.available` is deliberately
   * not consulted here: publishing it is what expresses the intent to present, so
   * treating it as a blocker would abandon every presentation at the reveal step.
   */
  private canPresent(generation: number): boolean {
    if (generation !== this.evaluationGeneration) {
      return false;
    }
    if (!this.service.isCommunity()) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    if (!facts.appVisible || facts.privacyMode === 'private') {
      return false;
    }
    return !this.surface.isReleaseNoticeBlocked(facts.promptBlockingFacts);
  }

  private withAvailability(available: boolean): CommunityUpdateCheckSnapshot {
    return {
      available: available,
      checking: false,
      checked: this.snapshot.checked,
      failed: this.snapshot.failed,
      currentVersionName: this.snapshot.currentVersionName,
      currentVersionCode: this.snapshot.currentVersionCode,
      versionName: this.snapshot.versionName,
      versionCode: this.snapshot.versionCode,
      title: this.snapshot.title,
      summary: this.snapshot.summary,
      items: this.snapshot.items,
      releaseUrl: this.snapshot.releaseUrl,
      statusMessage: this.snapshot.statusMessage
    };
  }

  private publish(snapshot: CommunityUpdateCheckSnapshot): void {
    this.snapshot = snapshot;
    this.shell.publishState(snapshot);
  }
}
