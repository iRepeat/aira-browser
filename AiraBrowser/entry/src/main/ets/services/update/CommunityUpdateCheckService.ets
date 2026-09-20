import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AppVersionIdentity, ChangelogContentService } from '../settings/ChangelogContentService';
import {
  CommunityReleaseFeedService,
  CommunityReleaseInfo
} from './CommunityReleaseFeedService';
import {
  CommunityUpdateCheckRepository,
  CommunityUpdateCheckRepositoryState
} from '../../data/update/CommunityUpdateCheckRepository';

export type CommunityUpdateCheckOutcome =
  'update_available' |
  'up_to_date' |
  'failed' |
  'not_applicable';

export interface CommunityUpdateCheckResult {
  outcome: CommunityUpdateCheckOutcome;
  current: AppVersionIdentity;
  release?: CommunityReleaseInfo;
  /** Human-readable one-liner for the manual entry point. */
  message: string;
}

/**
 * Checks the public Community release feed and decides whether the installed
 * bundle is behind it.
 *
 * This is persistence, transport, and policy only: it fetches, compares, and
 * remembers. Whether and when to *show* the result belongs to the presentation
 * coordinator, and the About page reuses the same check without touching any
 * browser surface.
 */
export class CommunityUpdateCheckService {
  private readonly repository: CommunityUpdateCheckRepository;
  private readonly feedService: CommunityReleaseFeedService;
  private readonly changelogService: ChangelogContentService;
  private checkInFlight?: Promise<CommunityUpdateCheckResult>;
  private lastRelease?: CommunityReleaseInfo;

  constructor(
    repository: CommunityUpdateCheckRepository,
    feedService: CommunityReleaseFeedService = new CommunityReleaseFeedService(),
    changelogService: ChangelogContentService = new ChangelogContentService()
  ) {
    this.repository = repository;
    this.feedService = feedService;
    this.changelogService = changelogService;
  }

  resolveCurrentVersion(): AppVersionIdentity {
    return this.changelogService.resolveCurrentVersion();
  }

  isCommunity(): boolean {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity();
  }

  async initialize(): Promise<void> {
    await this.repository.initialize().catch((_error: Error): void => {
    });
  }

  getRepositoryState(): CommunityUpdateCheckRepositoryState {
    return this.repository.getState();
  }

  getLastRelease(): CommunityReleaseInfo | undefined {
    return this.lastRelease;
  }

  async markNotified(versionCode: number): Promise<void> {
    await this.repository.markNotified(versionCode).catch((_error: Error): void => {
    });
  }

  /** Reuses an in-flight request instead of doubling the network call. */
  check(): Promise<CommunityUpdateCheckResult> {
    if (this.checkInFlight !== undefined) {
      return this.checkInFlight;
    }
    const promise = this.runCheck().finally((): void => {
      this.checkInFlight = undefined;
    });
    this.checkInFlight = promise;
    return promise;
  }

  private async runCheck(): Promise<CommunityUpdateCheckResult> {
    const current = this.resolveCurrentVersion();
    if (!this.isCommunity()) {
      return {
        outcome: 'not_applicable',
        current: current,
        message: '官方发行版通过应用市场更新。'
      };
    }
    await this.initialize();
    let release: CommunityReleaseInfo | undefined;
    try {
      release = await this.feedService.fetchLatestRelease();
    } catch (_error) {
      release = undefined;
    }
    if (release === undefined) {
      return {
        outcome: 'failed',
        current: current,
        message: '检查更新失败，请稍后再试。'
      };
    }
    this.lastRelease = release;
    await this.repository.recordCheckResult(release.versionName, release.versionCode).catch((_error: Error): void => {
    });
    const available = this.isRemoteNewer(current, release);
    return {
      outcome: available ? 'update_available' : 'up_to_date',
      current: current,
      release: release,
      message: available ? `发现新版本 ${release.versionName}` : `已是最新版本（${current.versionName}）`
    };
  }

  /**
   * A release published without an explicit `versionCode` falls back to a numeric
   * segment comparison, so the announcement still works for a hand-written tag.
   */
  private isRemoteNewer(current: AppVersionIdentity, release: CommunityReleaseInfo): boolean {
    if (release.versionCode > 0) {
      return release.versionCode > current.versionCode;
    }
    return this.compareVersionNames(release.versionName, current.versionName) > 0;
  }

  private compareVersionNames(left: string, right: string): number {
    const leftParts = left.split('.').map((part: string) => Number(part) || 0);
    const rightParts = right.split('.').map((part: string) => Number(part) || 0);
    const length = Math.max(leftParts.length, rightParts.length);
    for (let index = 0; index < length; index += 1) {
      const leftValue = leftParts[index] ?? 0;
      const rightValue = rightParts[index] ?? 0;
      if (leftValue !== rightValue) {
        return leftValue > rightValue ? 1 : -1;
      }
    }
    return 0;
  }
}
