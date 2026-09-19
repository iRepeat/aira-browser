import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_bottom_toolbar_guide';
const STATE_KEY: string = 'state_v1';

/**
 * Device-local memory for the one-time bottom-toolbar guide. It records only
 * presentation facts: that this device already told the user the floating
 * toolbar can be swiped down, and that the user asked not to be told again.
 * Nothing here changes how the toolbar itself behaves.
 */
export interface BottomToolbarGuideState {
  shownAt: number;
  completedAt: number;
}

export function buildEmptyBottomToolbarGuideState(): BottomToolbarGuideState {
  return {
    shownAt: 0,
    completedAt: 0
  };
}

export class BottomToolbarGuideRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: BottomToolbarGuideState = buildEmptyBottomToolbarGuideState();

  async initialize(): Promise<void> {
    const store = await this.getStore();
    this.state = this.normalizeState(store.getSync(STATE_KEY, '{}'));
  }

  getState(): BottomToolbarGuideState {
    return {
      shownAt: this.state.shownAt,
      completedAt: this.state.completedAt
    };
  }

  /**
   * Whether the guide is spent. A guide the user has already seen and a guide the
   * user explicitly refused both end the one-time announcement.
   */
  hasCompleted(): boolean {
    return this.state.shownAt > 0 || this.state.completedAt > 0;
  }

  async markShown(now: number = Date.now()): Promise<BottomToolbarGuideState> {
    return this.commit(now, false);
  }

  async markCompleted(now: number = Date.now()): Promise<BottomToolbarGuideState> {
    return this.commit(now, true);
  }

  private async commit(now: number, completed: boolean): Promise<BottomToolbarGuideState> {
    // The in-memory state flips before the write so the caller never re-evaluates
    // against a guide it has just spent, even while the flush is in flight.
    if (this.state.shownAt <= 0) {
      this.state.shownAt = now;
    }
    if (completed && this.state.completedAt <= 0) {
      this.state.completedAt = now;
    }
    await this.persist();
    return this.getState();
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
  }

  private normalizeState(value: preferences.ValueType): BottomToolbarGuideState {
    const raw = String(value ?? '').trim();
    if (raw.length === 0) {
      return buildEmptyBottomToolbarGuideState();
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, number | undefined> | undefined;
      return {
        shownAt: this.normalizeTimestamp(parsed?.shownAt),
        completedAt: this.normalizeTimestamp(parsed?.completedAt)
      };
    } catch (_error) {
      return buildEmptyBottomToolbarGuideState();
    }
  }

  private normalizeTimestamp(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}
