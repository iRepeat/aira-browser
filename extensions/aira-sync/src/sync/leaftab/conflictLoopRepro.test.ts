import { describe, expect, test } from 'vitest';
import type { LeafTabSyncBaselineStore } from './baseline';
import {
  LeafTabSyncEngine,
  LeafTabSyncLocalApplyVerificationError,
} from './engine';
import {
  LeafTabSyncTombstoneLifecycle,
  type LeafTabSyncHistoryStore,
} from './historyLifecycle';
import type {
  LeafTabSyncRemoteState,
  LeafTabSyncRemoteStore,
  LeafTabSyncWriteStateParams,
} from './remoteStore';
import type {
  LeafTabSyncBaseline,
  LeafTabSyncBookmarkItemEntity,
  LeafTabSyncHistoryDescriptor,
  LeafTabSyncSnapshot,
} from './schema';
import {
  LEAFTAB_LOCAL_APPLY_VERIFICATION_FAILURE_LIMIT,
  resolveLeafTabLocalApplyVerificationNextCount,
} from '@/features/sync/bookmarks/localApplyVerificationBreaker';

// 生产事故回归（uid 2029059012955225536，2026-10-11，Windows Chrome 插件）：
// 本地落地校验在被污染的书签树上确定性失败。旧引擎把这种失败当成普通错误：
// 远端每轮都被覆盖、基线永远不落、应用产生的书签事件又触发下一轮自动同步，
// 于是同一个"双向修改冲突"每轮被重新制造出来，弹窗无论点哪个按钮都会重现。
// 修复分两层：
//   引擎层——apply/verify 失败抛 LeafTabSyncLocalApplyVerificationError，
//             并在 steady-state 合并前用失控守卫拦下批量删除/重复扩散；
//   运行时层——连续失败达阈值后后台自动同步熔断（localApplyVerificationBreaker），
//             手动同步成功后解除。
// 注意：远端先写、确认后本地应用、成功才落基线的顺序是 ADR 0049 冻结契约，保持不变。

const EMPTY_TIMESTAMP = '1970-01-01T00:00:00.000Z';
const ORIGIN_HISTORY: LeafTabSyncHistoryDescriptor = {
  version: 1,
  epochId: 'bookmark-history-v1-origin',
  retainedFrom: EMPTY_TIMESTAMP,
};

const createItem = (
  id: string,
  title: string,
  url: string,
  updatedAt: string,
): LeafTabSyncBookmarkItemEntity => ({
  id,
  type: 'bookmark-item',
  parentId: null,
  title,
  url,
  createdAt: '2026-09-01T00:00:00.000Z',
  updatedAt,
  updatedBy: 'desktop-a',
  revision: 1,
});

const withItems = (deviceId: string, items: LeafTabSyncBookmarkItemEntity[]): LeafTabSyncSnapshot => ({
  meta: { version: 2, deviceId, generatedAt: '2026-09-02T00:00:00.000Z' },
  bookmarkFolders: {},
  bookmarkItems: Object.fromEntries(items.map((item) => [item.id, item])),
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: items.map((item) => item.id),
      updatedAt: '2026-09-02T00:00:00.000Z',
      updatedBy: deviceId,
      revision: 1,
    },
  },
  tombstones: {},
});

class MemoryBaselineStore implements LeafTabSyncBaselineStore {
  private value: LeafTabSyncBaseline | null = null;

  constructor(initial: LeafTabSyncBaseline | null = null) {
    this.value = initial;
  }

  async load(): Promise<LeafTabSyncBaseline | null> {
    return this.value;
  }

  async save(baseline: LeafTabSyncBaseline): Promise<void> {
    this.value = baseline;
  }
}

class MemoryHistoryStore implements LeafTabSyncHistoryStore {
  private value: LeafTabSyncHistoryDescriptor | null = null;

  async load(): Promise<LeafTabSyncHistoryDescriptor | null> {
    return this.value;
  }

  async save(history: LeafTabSyncHistoryDescriptor): Promise<void> {
    this.value = history;
  }
}

class MemoryRemoteStore implements LeafTabSyncRemoteStore {
  private current: LeafTabSyncRemoteState;
  writes: LeafTabSyncWriteStateParams[] = [];

  constructor(initial: LeafTabSyncRemoteState) {
    this.current = initial;
  }

  async readState(): Promise<LeafTabSyncRemoteState> {
    return this.current;
  }

  async writeState(params: LeafTabSyncWriteStateParams) {
    this.writes.push(params);
    const commitId = `c-write-${this.writes.length}`;
    this.current = {
      snapshot: params.snapshot,
      commitId,
      history: params.history,
    };
    return { commitId, writtenAt: '2026-10-11T13:00:00.000Z' };
  }
}

const createEngine = (options: {
  baselineStore: MemoryBaselineStore;
  remoteStore: MemoryRemoteStore;
  localSnapshot: () => Promise<LeafTabSyncSnapshot>;
  verify?: (snapshot: LeafTabSyncSnapshot) => void;
}) => {
  return new LeafTabSyncEngine({
    deviceId: 'desktop-a',
    remoteStore: options.remoteStore,
    baselineStore: options.baselineStore,
    historyLifecycle: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
    buildLocalSnapshot: options.localSnapshot,
    applyLocalSnapshot: async () => undefined,
    verifyLocalSnapshot: async (snapshot) => {
      options.verify?.(snapshot);
    },
    createEmptySnapshot: () => withItems('desktop-a', []),
  });
};

describe('冲突循环回归（生产事故机制）', () => {
  test('resolution 轮校验失败抛类型化错误，基线不动（供运行时熔断识别）', async () => {
    const baseSnapshot = withItems('desktop-a', [
      createItem('bkm_e', '原标题', 'https://e.com/', '2026-09-02T00:00:00.000Z'),
      createItem('bkm_f', 'F', 'https://f.com/', '2026-09-02T00:00:00.000Z'),
    ]);
    const localSnapshot = withItems('desktop-a', [
      createItem('bkm_e', '本机改后', 'https://e.com/', '2026-09-03T00:00:00.000Z'),
      createItem('bkm_f', 'F', 'https://f.com/', '2026-09-02T00:00:00.000Z'),
    ]);
    const remoteSnapshot = withItems('phone-b', [
      createItem('bkm_e', '云端改后', 'https://e.com/', '2026-09-04T00:00:00.000Z'),
      createItem('bkm_f', 'F', 'https://f.com/#changed', '2026-09-04T00:00:00.000Z'),
    ]);
    const baselineStore = new MemoryBaselineStore({
      commitId: 'c0',
      history: ORIGIN_HISTORY,
      snapshot: baseSnapshot,
      savedAt: '2026-09-02T00:00:00.000Z',
    });
    const remoteStore = new MemoryRemoteStore({
      snapshot: remoteSnapshot,
      commitId: 'c1',
      history: ORIGIN_HISTORY,
    });
    const engine = createEngine({
      baselineStore,
      remoteStore,
      localSnapshot: async () => localSnapshot,
      verify: () => {
        throw new Error('本地书签落地校验未通过，已停止提交同步基线。');
      },
    });

    // 不带 resolution：双向修改冲突（弹窗来源，行为不变）。
    const firstRun = await engine.sync();
    expect(firstRun.kind).toBe('conflict');
    expect(firstRun.mergeResult?.conflicts[0]?.id).toBe('bkm_e');

    // 点按钮后：按 ADR 顺序远端先写成功，本地校验失败以类型化错误抛出，
    // 基线保持未落——运行时据此计数并熔断，不再无限自动重试。
    await expect(
      engine.sync({ conflictResolution: 'prefer-local' }),
    ).rejects.toBeInstanceOf(LeafTabSyncLocalApplyVerificationError);
    expect(remoteStore.writes).toHaveLength(1);
    expect((await baselineStore.load())?.commitId).toBe('c0');

    // 校验恢复后同样一轮即可收敛（按钮语义不变）。
    let verifyBroken = true;
    const engineWithSwitch = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => {
        if (verifyBroken) throw new Error('本地书签落地校验未通过，已停止提交同步基线。');
      },
      createEmptySnapshot: () => withItems('desktop-a', []),
    });
    verifyBroken = false;
    const resolved = await engineWithSwitch.sync({ conflictResolution: 'prefer-local' });
    expect(resolved.kind).not.toBe('conflict');
    expect((await baselineStore.load())?.commitId).not.toBe('c0');
  });

  test('失控守卫：steady-state 一轮批量造重复会在写远端之前中止', async () => {
    // 基线里同一条书签只有 1 份；远端（被污染）带 60 份同内容不同 ID 的副本。
    const baseItems = [createItem('bkm_orig', '重复书签', 'https://dup.com/', '2026-09-02T00:00:00.000Z')];
    const remoteItems = [
      ...baseItems,
      ...Array.from({ length: 60 }, (_, index) => createItem(
        `bkm_dup_${index}`,
        '重复书签',
        'https://dup.com/',
        '2026-09-04T00:00:00.000Z',
      )),
    ];
    const baselineStore = new MemoryBaselineStore({
      commitId: 'c0',
      history: ORIGIN_HISTORY,
      snapshot: withItems('desktop-a', baseItems),
      savedAt: '2026-09-02T00:00:00.000Z',
    });
    const remoteStore = new MemoryRemoteStore({
      snapshot: withItems('phone-b', remoteItems),
      commitId: 'c1',
      history: ORIGIN_HISTORY,
    });
    const engine = createEngine({
      baselineStore,
      remoteStore,
      localSnapshot: async () => withItems('desktop-a', baseItems),
    });

    await expect(engine.sync()).rejects.toThrow(/重复书签/);
    // 关键：熔断发生在任何远端写入之前，污染不会扩散到本地之外。
    expect(remoteStore.writes).toHaveLength(0);
    expect((await baselineStore.load())?.commitId).toBe('c0');
  });

  test('失控守卫：steady-state 一轮删除过半书签会在写远端之前中止', async () => {
    const baseItems = Array.from({ length: 100 }, (_, index) => createItem(
      `bkm_base_${index}`,
      `书签 ${index}`,
      `https://example.com/${index}`,
      '2026-09-02T00:00:00.000Z',
    ));
    // 另一台设备明确删除了 70 条（墓碑需晚于 7 天保留边界才会被合并采纳）。
    const recentDeletedAt = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const remoteItems = baseItems.slice(0, 30);
    const remoteSnapshot: LeafTabSyncSnapshot = {
      ...withItems('phone-b', remoteItems),
      tombstones: Object.fromEntries(baseItems.slice(30).map((item) => [
        `bookmark-item|${item.id}`,
        {
          id: item.id,
          type: 'bookmark-item' as const,
          deletedAt: recentDeletedAt,
          deletedBy: 'phone-b',
          lastKnownRevision: item.revision,
        },
      ])),
    };
    const baselineStore = new MemoryBaselineStore({
      commitId: 'c0',
      history: ORIGIN_HISTORY,
      snapshot: withItems('desktop-a', baseItems),
      savedAt: '2026-09-02T00:00:00.000Z',
    });
    const remoteStore = new MemoryRemoteStore({
      snapshot: remoteSnapshot,
      commitId: 'c1',
      history: ORIGIN_HISTORY,
    });
    const engine = createEngine({
      baselineStore,
      remoteStore,
      localSnapshot: async () => withItems('desktop-a', baseItems),
    });

    await expect(engine.sync()).rejects.toThrow(/删除 70 条书签/);
    expect(remoteStore.writes).toHaveLength(0);
    expect((await baselineStore.load())?.commitId).toBe('c0');
  });

  test('断路器计数：连续第三次失败触发暂停，手动成功后由运行时清除', () => {
    expect(LEAFTAB_LOCAL_APPLY_VERIFICATION_FAILURE_LIMIT).toBe(3);
    expect(resolveLeafTabLocalApplyVerificationNextCount(0))
      .toEqual({ count: 1, paused: false });
    expect(resolveLeafTabLocalApplyVerificationNextCount(1))
      .toEqual({ count: 2, paused: false });
    expect(resolveLeafTabLocalApplyVerificationNextCount(2))
      .toEqual({ count: 3, paused: true });
  });
});
