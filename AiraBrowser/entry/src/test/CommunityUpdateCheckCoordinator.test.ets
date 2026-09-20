import { describe, expect, it } from '@ohos/hypium';
import {
  CommunityUpdateCheckCoordinator,
  CommunityUpdateCheckShell,
  CommunityUpdateCheckShellFacts,
  CommunityUpdateCheckSnapshot,
  CommunityUpdateCheckSurface
} from '../main/ets/core/update/CommunityUpdateCheckCoordinator';
import {
  CommunityUpdateCheckRepository,
  CommunityUpdateCheckRepositoryState,
  buildEmptyCommunityUpdateCheckState
} from '../main/ets/data/update/CommunityUpdateCheckRepository';
import {
  CommunityReleaseFeedService,
  CommunityReleaseInfo
} from '../main/ets/services/update/CommunityReleaseFeedService';
import {
  CommunityUpdateCheckService
} from '../main/ets/services/update/CommunityUpdateCheckService';
import {
  AppVersionIdentity,
  ChangelogContentService
} from '../main/ets/services/settings/ChangelogContentService';
import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceId,
  BrowserTransientSurfacePresentationRequest,
  BrowserTransientSurfaceToken
} from '../main/ets/core/browser/BrowserTransientSurfaceCoordinator';

const COMMUNITY_UPDATE_SURFACE_ID: BrowserTransientSurfaceId = 'community_update';

function cloneState(state: CommunityUpdateCheckRepositoryState): CommunityUpdateCheckRepositoryState {
  return {
    lastCheckedAt: state.lastCheckedAt,
    lastRemoteVersionName: state.lastRemoteVersionName,
    lastRemoteVersionCode: state.lastRemoteVersionCode,
    lastNotifiedVersionCode: state.lastNotifiedVersionCode,
    updatedAt: state.updatedAt
  };
}

function buildIdlePromptBlockingFacts(): BrowserTransientPromptBlockingFacts {
  return {
    tabsSheetVisible: false,
    readerModeVisible: false,
    releaseNoticeVisible: false,
    hlsTakeoverVisible: false,
    topFloatingPromptVisible: false,
    webContextMenuVisible: false,
    pendingJavaScriptPrompt: false,
    pendingSitePermissionPrompt: false,
    manualElementHideSelectionActive: false,
    privateModeLockVisible: false,
    downloadPromptVisible: false
  };
}

class FixtureCommunityUpdateCheckRepository extends CommunityUpdateCheckRepository {
  stored: CommunityUpdateCheckRepositoryState = buildEmptyCommunityUpdateCheckState();
  memory: CommunityUpdateCheckRepositoryState = buildEmptyCommunityUpdateCheckState();

  async initialize(): Promise<CommunityUpdateCheckRepositoryState> {
    this.memory = cloneState(this.stored);
    return this.getState();
  }

  isInitialized(): boolean {
    return true;
  }

  getState(): CommunityUpdateCheckRepositoryState {
    return cloneState(this.memory);
  }

  async recordCheckResult(
    remoteVersionName: string,
    remoteVersionCode: number,
    now: number = Date.now()
  ): Promise<CommunityUpdateCheckRepositoryState> {
    this.memory.lastCheckedAt = now;
    this.memory.lastRemoteVersionName = remoteVersionName;
    this.memory.lastRemoteVersionCode = remoteVersionCode;
    return this.getState();
  }

  async markNotified(versionCode: number, now: number = Date.now()): Promise<CommunityUpdateCheckRepositoryState> {
    this.memory.lastNotifiedVersionCode = versionCode;
    this.memory.updatedAt = now;
    return this.getState();
  }
}

class FixtureCommunityReleaseFeedService extends CommunityReleaseFeedService {
  release?: CommunityReleaseInfo;

  async fetchLatestRelease(): Promise<CommunityReleaseInfo | undefined> {
    return this.release;
  }
}

class FixtureChangelogContentService extends ChangelogContentService {
  current: AppVersionIdentity = { versionName: '3.2.3', versionCode: 1000439 };

  resolveCurrentVersion(): AppVersionIdentity {
    return {
      versionName: this.current.versionName,
      versionCode: this.current.versionCode
    };
  }
}

class FixtureCommunityUpdateCheckSurface implements CommunityUpdateCheckSurface {
  presentRequests: BrowserTransientSurfacePresentationRequest[] = [];
  dismissedIds: BrowserTransientSurfaceId[] = [];
  automaticPromptBlocked: boolean = false;

  present = (request: BrowserTransientSurfacePresentationRequest): BrowserTransientSurfaceToken => {
    this.presentRequests.push(request);
    return {
      id: request.id,
      generation: this.presentRequests.length
    };
  };

  dismiss = (id: BrowserTransientSurfaceId): void => {
    this.dismissedIds.push(id);
  };

  isReleaseNoticeBlocked = (_facts: BrowserTransientPromptBlockingFacts): boolean => {
    return this.automaticPromptBlocked;
  };
}

class FixtureCommunityUpdateCheckShell implements CommunityUpdateCheckShell {
  facts: CommunityUpdateCheckShellFacts = {
    appVisible: true,
    privacyMode: 'normal',
    promptBlockingFacts: buildIdlePromptBlockingFacts()
  };
  publishedSnapshots: CommunityUpdateCheckSnapshot[] = [];
  openedUrls: string[] = [];
  toasts: string[] = [];

  resolveFacts(): CommunityUpdateCheckShellFacts {
    return this.facts;
  }

  publishState(snapshot: CommunityUpdateCheckSnapshot): void {
    this.publishedSnapshots.push(snapshot);
  }

  openReleasePage(url: string): void {
    this.openedUrls.push(url);
  }

  showToast(message: string): void {
    this.toasts.push(message);
  }
}

interface CommunityUpdateFixture {
  repository: FixtureCommunityUpdateCheckRepository;
  feed: FixtureCommunityReleaseFeedService;
  service: CommunityUpdateCheckService;
  surface: FixtureCommunityUpdateCheckSurface;
  shell: FixtureCommunityUpdateCheckShell;
  coordinator: CommunityUpdateCheckCoordinator;
}

function buildNewerRelease(): CommunityReleaseInfo {
  return {
    versionName: '3.3.0',
    versionCode: 1000445,
    tagName: 'v3.3.0',
    releaseUrl: 'https://github.com/mason173/aira-browser/releases/tag/v3.3.0',
    title: 'Aira Community 3.3.0 (1000445)',
    publishedAt: '2026-10-01',
    summary: '这一版带来了一些改进。',
    items: ['修复了一个问题。', '改进了体验。']
  };
}

function buildCommunityUpdateFixture(): CommunityUpdateFixture {
  const repository = new FixtureCommunityUpdateCheckRepository();
  const feed = new FixtureCommunityReleaseFeedService();
  const changelog = new FixtureChangelogContentService();
  const service = new CommunityUpdateCheckService(repository, feed, changelog);
  const surface = new FixtureCommunityUpdateCheckSurface();
  const shell = new FixtureCommunityUpdateCheckShell();
  // A zero delay keeps the test on the same scheduling path the shell uses while
  // staying deterministic.
  const coordinator = new CommunityUpdateCheckCoordinator(service, surface, shell, 0);
  return {
    repository: repository,
    feed: feed,
    service: service,
    surface: surface,
    shell: shell,
    coordinator: coordinator
  };
}

async function flushEvaluation(): Promise<void> {
  for (let turn = 0; turn < 3; turn += 1) {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }
}

export default function communityUpdateCheckCoordinatorTest(): void {
  describe('CommunityUpdateCheckCoordinator', () => {
    it('announces a newer Community release and spends it only after it reveals', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      fixture.feed.release = buildNewerRelease();

      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(1);
      expect(fixture.surface.presentRequests[0].id).assertEqual(COMMUNITY_UPDATE_SURFACE_ID);
      expect(fixture.coordinator.getSnapshot().available).assertTrue();
      expect(fixture.coordinator.getSnapshot().versionName).assertEqual('3.3.0');

      // The one-time record is only spent once the card actually reached the user.
      expect(fixture.repository.memory.lastNotifiedVersionCode).assertEqual(0);
      fixture.coordinator.handleSurfaceRevealed();
      expect(fixture.repository.memory.lastNotifiedVersionCode).assertEqual(1000445);
    });

    it('stays quiet when the installed build already matches the feed', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      const current = buildNewerRelease();
      fixture.feed.release = {
        versionName: '3.2.3',
        versionCode: 1000439,
        tagName: current.tagName,
        releaseUrl: current.releaseUrl,
        title: current.title,
        publishedAt: current.publishedAt,
        summary: current.summary,
        items: current.items
      };

      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(0);
      expect(fixture.coordinator.getSnapshot().available).assertFalse();
    });

    it('does not announce the same release twice', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      fixture.repository.stored.lastNotifiedVersionCode = 1000445;
      fixture.feed.release = buildNewerRelease();

      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(0);
    });

    it('waits for a free lane instead of dropping the pending notice', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      fixture.feed.release = buildNewerRelease();
      fixture.surface.automaticPromptBlocked = true;

      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.surface.automaticPromptBlocked = false;
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('never announces inside a private session', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      fixture.feed.release = buildNewerRelease();
      fixture.shell.facts.privacyMode = 'private';

      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(0);
    });

    it('keeps one check path for the manual About entry point', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      fixture.feed.release = buildNewerRelease();

      const result = await fixture.service.check();

      expect(result.outcome).assertEqual('update_available');
      expect(result.message).assertEqual('发现新版本 3.3.0');
      expect(result.release?.versionCode).assertEqual(1000445);
      expect(fixture.repository.memory.lastRemoteVersionCode).assertEqual(1000445);
    });

    it('opens the release page and dismisses on the primary action', 0, async () => {
      const fixture = buildCommunityUpdateFixture();
      fixture.feed.release = buildNewerRelease();
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();

      fixture.coordinator.handleAction('open_release_page');

      expect(fixture.shell.openedUrls.length).assertEqual(1);
      expect(fixture.shell.openedUrls[0]).assertEqual(
        'https://github.com/mason173/aira-browser/releases/tag/v3.3.0'
      );
      expect(fixture.surface.dismissedIds.length).assertEqual(1);
      expect(fixture.coordinator.getSnapshot().available).assertFalse();
    });
  });
}
