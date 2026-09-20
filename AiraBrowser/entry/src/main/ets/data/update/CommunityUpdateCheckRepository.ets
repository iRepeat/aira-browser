import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_community_update_check';
const STATE_KEY: string = 'state_v1';

/**
 * Local memory for the Community update check. It deliberately stores only
 * presentation facts: when the feed was last read, which remote version it last
 * reported, and which remote version has already been announced. It never stores
 * or derives the installed version, which stays owned by the bundle manager.
 */
export interface CommunityUpdateCheckRepositoryState {
  lastCheckedAt: number;
  lastRemoteVersionName: string;
  lastRemoteVersionCode: number;
  lastNotifiedVersionCode: number;
  updatedAt: number;
}

export function buildEmptyCommunityUpdateCheckState(): CommunityUpdateCheckRepositoryState {
  return {
    lastCheckedAt: 0,
    lastRemoteVersionName: '',
    lastRemoteVersionCode: 0,
    lastNotifiedVersionCode: 0,
    updatedAt: 0
  };
}

export class CommunityUpdateCheckRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: CommunityUpdateCheckRepositoryState = buildEmptyCommunityUpdateCheckState();
  private initialized: boolean = false;

  async initialize(): Promise<CommunityUpdateCheckRepositoryState> {
    const store = await this.getStore();
    this.state = this.normalizeState(store.getSync(STATE_KEY, JSON.stringify(buildEmptyCommunityUpdateCheckState())));
    this.initialized = true;
    return this.getState();
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  getState(): CommunityUpdateCheckRepositoryState {
    return this.cloneState(this.state);
  }

  async recordCheckResult(
    remoteVersionName: string,
    remoteVersionCode: number,
    now: number = Date.now()
  ): Promise<CommunityUpdateCheckRepositoryState> {
    this.state.lastCheckedAt = this.normalizeTimestamp(now);
    this.state.lastRemoteVersionName = remoteVersionName.trim();
    this.state.lastRemoteVersionCode = this.normalizeCount(remoteVersionCode);
    this.state.updatedAt = this.state.lastCheckedAt;
    await this.persist();
    return this.getState();
  }

  async markNotified(versionCode: number, now: number = Date.now()): Promise<CommunityUpdateCheckRepositoryState> {
    this.state.lastNotifiedVersionCode = this.normalizeCount(versionCode);
    this.state.updatedAt = this.normalizeTimestamp(now);
    await this.persist();
    return this.getState();
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
  }

  private normalizeState(value: preferences.ValueType): CommunityUpdateCheckRepositoryState {
    try {
      const parsed = JSON.parse(String(value)) as CommunityUpdateCheckRepositoryState;
      return {
        lastCheckedAt: this.normalizeTimestamp(parsed.lastCheckedAt),
        lastRemoteVersionName: `${parsed.lastRemoteVersionName ?? ''}`.trim(),
        lastRemoteVersionCode: this.normalizeCount(parsed.lastRemoteVersionCode),
        lastNotifiedVersionCode: this.normalizeCount(parsed.lastNotifiedVersionCode),
        updatedAt: this.normalizeTimestamp(parsed.updatedAt)
      };
    } catch (_error) {
      return buildEmptyCommunityUpdateCheckState();
    }
  }

  private normalizeCount(value: number | undefined): number {
    const count = Number(value);
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 0;
  }

  private normalizeTimestamp(value: number | undefined): number {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.round(timestamp) : 0;
  }

  private cloneState(state: CommunityUpdateCheckRepositoryState): CommunityUpdateCheckRepositoryState {
    return {
      lastCheckedAt: state.lastCheckedAt,
      lastRemoteVersionName: state.lastRemoteVersionName,
      lastRemoteVersionCode: state.lastRemoteVersionCode,
      lastNotifiedVersionCode: state.lastNotifiedVersionCode,
      updatedAt: state.updatedAt
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}
