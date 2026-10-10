import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import {
  APP_REVIEW_ALREADY_COMMENTED_ERROR_CODES,
  AppReviewPromptCoordinator,
  AppReviewPromptShell,
  AppReviewPromptShellFacts,
  AppReviewPromptSurface
} from '../main/ets/core/review/AppReviewPromptCoordinator';
import {
  AppReviewPromptRepository,
  AppReviewPromptState
} from '../main/ets/data/review/AppReviewPromptRepository';
import {
  SystemSettingsLaunchResult,
  SystemSettingsLaunchService
} from '../main/ets/services/system/SystemSettingsLaunchService';
import {
  BrowserTransientPromptBlockingFacts
} from '../main/ets/core/browser/BrowserTransientSurfaceCoordinator';

const APPGALLERY_CONNECTION_ERROR_CODE: number = 1021500003;
const HUAWEI_ID_NOT_SIGNED_IN_ERROR_CODE: number = 1021500006;

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

function buildEligibleState(now: number): AppReviewPromptState {
  return {
    firstSeenAt: now - 100 * 24 * 60 * 60 * 1000,
    launchCount: 10,
    regularPageVisitCount: 50,
    promptCount: 0,
    lastPromptAt: 0,
    lastDeferredAt: 0,
    suppressedAt: 0,
    acceptedAt: 0,
    acceptedVersionName: '',
    lastAction: 'none',
    updatedAt: now
  };
}

/** In-memory stand-in for the preferences-backed review prompt memory. */
class FixtureAppReviewPromptRepository extends AppReviewPromptRepository {
  memory: AppReviewPromptState = buildEligibleState(Date.now());
  shownCount: number = 0;
  attemptFailedCount: number = 0;
  acceptCalls: string[] = [];
  commentAlreadyPresentCalls: string[] = [];

  getState(): AppReviewPromptState {
    const snapshot = this.memory;
    return {
      firstSeenAt: snapshot.firstSeenAt,
      launchCount: snapshot.launchCount,
      regularPageVisitCount: snapshot.regularPageVisitCount,
      promptCount: snapshot.promptCount,
      lastPromptAt: snapshot.lastPromptAt,
      lastDeferredAt: snapshot.lastDeferredAt,
      suppressedAt: snapshot.suppressedAt,
      acceptedAt: snapshot.acceptedAt,
      acceptedVersionName: snapshot.acceptedVersionName,
      lastAction: snapshot.lastAction,
      updatedAt: snapshot.updatedAt
    };
  }

  async markPromptShown(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.shownCount += 1;
    this.memory.promptCount += 1;
    this.memory.lastPromptAt = now;
    this.memory.lastAction = 'shown';
    return this.getState();
  }

  async markPromptAttemptFailed(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.attemptFailedCount += 1;
    this.memory.lastPromptAt = now;
    this.memory.lastAction = 'failed';
    return this.getState();
  }

  async accept(versionName: string, now: number = Date.now()): Promise<AppReviewPromptState> {
    this.acceptCalls.push(versionName);
    this.memory.acceptedAt = now;
    this.memory.acceptedVersionName = versionName.trim();
    this.memory.lastAction = 'accepted';
    return this.getState();
  }

  async markCommentAlreadyPresent(versionName: string, now: number = Date.now()): Promise<AppReviewPromptState> {
    this.commentAlreadyPresentCalls.push(versionName);
    this.memory.acceptedAt = now;
    this.memory.acceptedVersionName = versionName.trim();
    this.memory.lastAction = 'accepted';
    return this.getState();
  }
}

class FixtureSystemSettingsLaunchService extends SystemSettingsLaunchService {
  results: SystemSettingsLaunchResult[] = [];
  showPromptCalls: number = 0;

  async showAppReviewPrompt(_context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    this.showPromptCalls += 1;
    const result = this.results.shift();
    if (result !== undefined) {
      return result;
    }
    return { success: true, message: 'opened' };
  }
}

class FixtureAppReviewPromptSurface implements AppReviewPromptSurface {
  blocked: boolean = false;

  isAppReviewPromptBlocked = (_facts: BrowserTransientPromptBlockingFacts): boolean => {
    return this.blocked;
  };
}

class FixtureAppReviewPromptShell implements AppReviewPromptShell {
  facts: AppReviewPromptShellFacts = {
    context: undefined as ESObject as common.UIAbilityContext,
    homeVisible: true,
    privateMode: false,
    appVisible: true,
    promptBlockingFacts: buildIdlePromptBlockingFacts()
  };

  resolveFacts(): AppReviewPromptShellFacts {
    return this.facts;
  }
}

interface ReviewFixture {
  repository: FixtureAppReviewPromptRepository;
  launchService: FixtureSystemSettingsLaunchService;
  surface: FixtureAppReviewPromptSurface;
  shell: FixtureAppReviewPromptShell;
  coordinator: AppReviewPromptCoordinator;
}

function buildReviewFixture(): ReviewFixture {
  const repository = new FixtureAppReviewPromptRepository();
  const launchService = new FixtureSystemSettingsLaunchService();
  const surface = new FixtureAppReviewPromptSurface();
  const shell = new FixtureAppReviewPromptShell();
  const coordinator = new AppReviewPromptCoordinator(
    repository,
    launchService,
    surface,
    shell,
    0
  );
  return { repository, launchService, surface, shell, coordinator };
}

async function runScheduledEvaluation(): Promise<void> {
  await new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 5);
  });
  for (let turn = 0; turn < 6; turn += 1) {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }
}

export default function appReviewPromptCoordinatorTest(): void {
  describe('AppReviewPromptCoordinator', () => {
    it('records a shown prompt after the system dialog opens successfully', 0, async () => {
      const fixture = buildReviewFixture();
      fixture.launchService.results.push({ success: true, message: 'opened' });

      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();

      expect(fixture.launchService.showPromptCalls).assertEqual(1);
      expect(fixture.repository.shownCount).assertEqual(1);
      expect(fixture.repository.getState().lastAction).assertEqual('shown');

      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();
      expect(fixture.launchService.showPromptCalls).assertEqual(1);
    });

    it('backs off silently when the system dialog cannot open and does not retry per home visit', 0, async () => {
      const fixture = buildReviewFixture();
      fixture.launchService.results.push({
        success: false,
        message: 'failed',
        errorCode: APPGALLERY_CONNECTION_ERROR_CODE
      });

      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();

      expect(fixture.launchService.showPromptCalls).assertEqual(1);
      expect(fixture.repository.attemptFailedCount).assertEqual(1);
      expect(fixture.repository.shownCount).assertEqual(0);
      expect(fixture.repository.getState().lastAction).assertEqual('failed');
      expect(fixture.repository.getState().lastPromptAt > 0).assertTrue();
      expect(fixture.repository.getState().promptCount).assertEqual(0);

      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();
      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();
      expect(fixture.launchService.showPromptCalls).assertEqual(1);
    });

    it('treats a not-signed-in failure the same as any other failed attempt', 0, async () => {
      const fixture = buildReviewFixture();
      fixture.launchService.results.push({
        success: false,
        message: 'failed',
        errorCode: HUAWEI_ID_NOT_SIGNED_IN_ERROR_CODE
      });

      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();

      expect(fixture.repository.getState().lastAction).assertEqual('failed');
      expect(fixture.repository.acceptCalls.length).assertEqual(0);
      expect(fixture.repository.commentAlreadyPresentCalls.length).assertEqual(0);
    });

    it('treats already-commented errors as an accepted invitation and stops asking', 0, async () => {
      const alreadyCommentedCodes = APP_REVIEW_ALREADY_COMMENTED_ERROR_CODES;
      for (let index = 0; index < alreadyCommentedCodes.length; index += 1) {
        const fixture = buildReviewFixture();
        fixture.launchService.results.push({
          success: false,
          message: 'failed',
          errorCode: alreadyCommentedCodes[index]
        });

        fixture.coordinator.scheduleEvaluation();
        await runScheduledEvaluation();

        expect(fixture.repository.commentAlreadyPresentCalls.length).assertEqual(1);
        expect(fixture.repository.commentAlreadyPresentCalls[0].length > 0).assertTrue();
        expect(fixture.repository.getState().lastAction).assertEqual('accepted');
        expect(fixture.repository.attemptFailedCount).assertEqual(0);

        fixture.coordinator.scheduleEvaluation();
        await runScheduledEvaluation();
        expect(fixture.launchService.showPromptCalls).assertEqual(1);
      }
    });

    it('does not launch the system dialog when a blocking surface is visible', 0, async () => {
      const fixture = buildReviewFixture();
      fixture.surface.blocked = true;

      fixture.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();

      expect(fixture.launchService.showPromptCalls).assertEqual(0);
      expect(fixture.repository.shownCount).assertEqual(0);
    });

    it('does not launch the system dialog away from the visible home surface', 0, async () => {
      const hiddenHome = buildReviewFixture();
      hiddenHome.shell.facts.homeVisible = false;
      hiddenHome.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();
      expect(hiddenHome.launchService.showPromptCalls).assertEqual(0);

      const privateHome = buildReviewFixture();
      privateHome.shell.facts.privateMode = true;
      privateHome.coordinator.scheduleEvaluation();
      await runScheduledEvaluation();
      expect(privateHome.launchService.showPromptCalls).assertEqual(0);
    });
  });
}
