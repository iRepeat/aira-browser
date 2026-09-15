import { describe, expect, test } from 'vitest';
import { mergeLeafTabSyncSnapshot, mergeLeafTabSyncSnapshotWithoutBaseline } from './merge';
import {
  parseCanonicalLeafTabSyncWireSnapshot,
  toLeafTabSyncWireSnapshot,
  type LeafTabSyncSnapshot,
  type LeafTabSyncTombstone,
} from './schema';

const T0 = '2026-08-04T00:00:00.000Z';
const T1 = '2026-08-04T00:01:00.000Z';
const ROOT_ID = 'browser_root_toolbar';
const COLLIDING_ID = 'cross-type-id';
const COLLIDING_FOLDER_ID = 'folder-shared';
const FOLDER_CHILD_ID = 'folder-child';

const createSnapshot = (
  deviceId: string,
  options: {
    includeLiveItem?: boolean;
    includeFolderTombstone?: boolean;
    includeItemTombstone?: boolean;
  } = {},
): LeafTabSyncSnapshot => ({
  meta: { version: 2, deviceId, generatedAt: T0 },
  bookmarkFolders: {
    [ROOT_ID]: {
      id: ROOT_ID,
      type: 'bookmark-folder',
      parentId: null,
      title: 'Root',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    },
  },
  bookmarkItems: options.includeLiveItem ? {
    [COLLIDING_ID]: {
      id: COLLIDING_ID,
      type: 'bookmark-item',
      parentId: ROOT_ID,
      title: 'Live item',
      url: 'https://example.com/live',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    },
  } : {},
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: [ROOT_ID],
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    },
    [ROOT_ID]: {
      type: 'bookmark-order',
      parentId: ROOT_ID,
      ids: options.includeLiveItem ? [COLLIDING_ID] : [],
      updatedAt: T0,
      updatedBy: deviceId,
      revision: options.includeLiveItem ? 2 : 1,
    },
  },
  tombstones: options.includeFolderTombstone || options.includeItemTombstone ? {
    [`${options.includeItemTombstone ? 'bookmark-item' : 'bookmark-folder'}|${COLLIDING_ID}`]: {
      id: COLLIDING_ID,
      type: options.includeItemTombstone ? 'bookmark-item' : 'bookmark-folder',
      deletedAt: T0,
      deletedBy: deviceId,
      lastKnownRevision: 1,
    },
  } : {},
});

const createFolderCollisionSnapshot = (
  deviceId: string,
  folderTitle: string,
): LeafTabSyncSnapshot => {
  const snapshot = createSnapshot(deviceId);
  snapshot.bookmarkFolders[COLLIDING_FOLDER_ID] = {
    id: COLLIDING_FOLDER_ID,
    type: 'bookmark-folder',
    parentId: ROOT_ID,
    title: folderTitle,
    createdAt: T0,
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1,
  };
  snapshot.bookmarkItems[FOLDER_CHILD_ID] = {
    id: FOLDER_CHILD_ID,
    type: 'bookmark-item',
    parentId: COLLIDING_FOLDER_ID,
    title: 'Folder child',
    url: 'https://example.com/folder-child',
    createdAt: T0,
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1,
  };
  snapshot.bookmarkOrders[ROOT_ID].ids = [COLLIDING_FOLDER_ID];
  snapshot.bookmarkOrders[COLLIDING_FOLDER_ID] = {
    type: 'bookmark-order',
    parentId: COLLIDING_FOLDER_ID,
    ids: [FOLDER_CHILD_ID],
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1,
  };
  return snapshot;
};

const createMigrationSnapshot = (
  deviceId: string,
  itemId: string,
): LeafTabSyncSnapshot => {
  const snapshot = createSnapshot(deviceId, { includeLiveItem: true });
  const item = snapshot.bookmarkItems[COLLIDING_ID];
  delete snapshot.bookmarkItems[COLLIDING_ID];
  snapshot.bookmarkItems[itemId] = { ...item, id: itemId };
  snapshot.bookmarkOrders[ROOT_ID].ids = [itemId];
  return snapshot;
};

const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

describe('mergeLeafTabSyncSnapshot', () => {
  test('keeps a canonical result when a live entity meets an opposite-type tombstone with the same ID', () => {
    const base = createSnapshot('baseline');
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    const remote = createSnapshot('phone-a', { includeFolderTombstone: true });

    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(local))).not.toBeNull();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(remote))).not.toBeNull();

    const merged = mergeLeafTabSyncSnapshot(base, local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(merged.bookmarkItems[COLLIDING_ID]).toBeDefined();
    expect(merged.tombstones[`bookmark-folder|${COLLIDING_ID}`]).toBeUndefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });

  test('applies the same opposite-type rule when no provider baseline exists', () => {
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    const remote = createSnapshot('phone-a', { includeFolderTombstone: true });

    const merged = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(merged.bookmarkItems[COLLIDING_ID]).toBeDefined();
    expect(merged.tombstones[`bookmark-folder|${COLLIDING_ID}`]).toBeUndefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });

  test('collapses a current-device stable ID onto its matching legacy migration ID', () => {
    const local = createMigrationSnapshot('desktop-a', 'bkm_local_desktop-a_bookmark-1');
    const remote = createMigrationSnapshot('phone-a', 'bkm_same-bookmark_legacy');

    const merged = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(Object.keys(merged.bookmarkItems)).toEqual(['bkm_same-bookmark_legacy']);
    expect(merged.bookmarkOrders[ROOT_ID].ids).toEqual(['bkm_same-bookmark_legacy']);
  });

  test('converges an already duplicated legacy and stable pair without deleting intentional multiplicity', () => {
    const local = createMigrationSnapshot('desktop-a', 'bkm_local_desktop-a_bookmark-1');
    const localSecond = {
      ...local.bookmarkItems['bkm_local_desktop-a_bookmark-1'],
      id: 'bkm_legacy-second',
    };
    local.bookmarkItems[localSecond.id] = localSecond;
    local.bookmarkOrders[ROOT_ID].ids = [localSecond.id, 'bkm_local_desktop-a_bookmark-1'];

    const remote = createMigrationSnapshot('phone-a', 'bkm_legacy-first');
    const remoteSecond = {
      ...remote.bookmarkItems['bkm_legacy-first'],
      id: 'bkm_local_desktop-a_bookmark-2',
    };
    remote.bookmarkItems[remoteSecond.id] = remoteSecond;
    remote.bookmarkOrders[ROOT_ID].ids = ['bkm_legacy-first', remoteSecond.id];

    const merged = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(Object.keys(merged.bookmarkItems).sort()).toEqual([
      'bkm_legacy-first',
      'bkm_legacy-second',
    ]);
    expect(merged.bookmarkOrders[ROOT_ID].ids.sort()).toEqual([
      'bkm_legacy-first',
      'bkm_legacy-second',
    ]);
  });

  test('does not collapse a stable ID owned by another device', () => {
    const local = createMigrationSnapshot('desktop-a', 'bkm_local_phone-a_bookmark-1');
    const remote = createMigrationSnapshot('phone-a', 'bkm_same-bookmark_legacy');

    const merged = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(Object.keys(merged.bookmarkItems).sort()).toEqual([
      'bkm_local_phone-a_bookmark-1',
      'bkm_same-bookmark_legacy',
    ]);
  });

  test('does not let delimiter characters create a false migration match', () => {
    const local = createMigrationSnapshot('desktop-a', 'bkm_local_desktop-a_bookmark-1');
    local.bookmarkItems['bkm_local_desktop-a_bookmark-1'].title = 'A|B';
    local.bookmarkItems['bkm_local_desktop-a_bookmark-1'].url = 'https://example.com/a|b';
    const remote = createMigrationSnapshot('phone-a', 'bkm_legacy-parent|A');
    remote.bookmarkItems['bkm_legacy-parent|A'].title = 'A';
    remote.bookmarkItems['bkm_legacy-parent|A'].url = 'B|https://example.com/a|b';

    const merged = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(Object.keys(merged.bookmarkItems).sort()).toEqual([
      'bkm_legacy-parent|A',
      'bkm_local_desktop-a_bookmark-1',
    ]);
  });

  test('still propagates an ordinary same-type deletion', () => {
    const baseline = createSnapshot('baseline', { includeLiveItem: true });
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    const remote = createSnapshot('phone-a', { includeItemTombstone: true });

    const merged = mergeLeafTabSyncSnapshot(baseline, local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(merged.bookmarkItems[COLLIDING_ID]).toBeUndefined();
    expect(merged.tombstones[`bookmark-item|${COLLIDING_ID}`]).toBeDefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });

  test('allows a preservation duplicate folder and its children to be deleted on the next sync', () => {
    const firstMerge = mergeLeafTabSyncSnapshotWithoutBaseline(
      createFolderCollisionSnapshot('desktop-a', 'Desktop folder'),
      createFolderCollisionSnapshot('phone-a', 'Phone folder'),
      { deviceId: 'desktop-a', generatedAt: T0 },
    ).snapshot;
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(firstMerge))).not.toBeNull();

    const preservedFolderId = Object.keys(firstMerge.bookmarkFolders).find((id) => (
      id !== ROOT_ID && id !== COLLIDING_FOLDER_ID
    ));
    expect(preservedFolderId).toBeDefined();
    const preservedChild = Object.values(firstMerge.bookmarkItems).find((item) => (
      item.parentId === preservedFolderId
    ));
    expect(preservedChild).toBeDefined();

    const localAfterDelete = clone(firstMerge);
    const deletedFolder = localAfterDelete.bookmarkFolders[preservedFolderId!];
    delete localAfterDelete.bookmarkFolders[preservedFolderId!];
    delete localAfterDelete.bookmarkItems[preservedChild!.id];
    delete localAfterDelete.bookmarkOrders[preservedFolderId!];
    Object.values(localAfterDelete.bookmarkOrders).forEach((order) => {
      order.ids = order.ids.filter((id) => id !== preservedFolderId && id !== preservedChild!.id);
    });
    localAfterDelete.tombstones[`bookmark-folder|${preservedFolderId}`] = {
      id: preservedFolderId!,
      type: 'bookmark-folder',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: deletedFolder.revision,
    };
    localAfterDelete.tombstones[`bookmark-item|${preservedChild!.id}`] = {
      id: preservedChild!.id,
      type: 'bookmark-item',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: preservedChild!.revision,
    };
    localAfterDelete.meta.generatedAt = T1;
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(localAfterDelete))).not.toBeNull();

    const merged = mergeLeafTabSyncSnapshot(firstMerge, localAfterDelete, firstMerge, {
      deviceId: 'desktop-a',
      generatedAt: T1,
    }).snapshot;

    expect(merged.bookmarkFolders[preservedFolderId!]).toBeUndefined();
    expect(merged.bookmarkItems[preservedChild!.id]).toBeUndefined();
    expect(merged.bookmarkOrders[preservedFolderId!]).toBeUndefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });
});

describe('missing-baseline deletion is not a delete-vs-edit conflict', () => {
  // A first join has no shared ancestor, so neither side can be proven to have edited
  // anything. A surviving tombstone is therefore a deletion instruction, exactly as the App's
  // mergeMissingBaselineDataSets already treats it (docs/aira-bookmark-canonical-identity-design.md 6.1b).
  // Reporting a conflict here asked the user to arbitrate content they never changed, and the
  // dialog could not be resolved because the no-baseline rerun re-derived the same conflict.
  const tombstoneFor = (id: string, lastKnownRevision: number): LeafTabSyncTombstone => ({
    id,
    type: 'bookmark-item',
    deletedAt: T0,
    deletedBy: 'phone-a',
    lastKnownRevision,
  });

  test('a locally edited item against a remote tombstone deletes instead of asking the user', () => {
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    local.bookmarkItems[COLLIDING_ID].title = 'Desktop edit';
    local.bookmarkItems[COLLIDING_ID].revision = 2;
    const remote = createSnapshot('phone-a', { includeItemTombstone: true });

    const result = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    });

    expect(result.conflicts).toEqual([]);
    expect(result.snapshot.bookmarkItems[COLLIDING_ID]).toBeUndefined();
    expect(result.snapshot.tombstones[`bookmark-item|${COLLIDING_ID}`]).toBeDefined();
  });

  test('a local tombstone against a remote live item also reports no conflict', () => {
    // This direction is settled earlier: a first join drops the local tombstone when the remote
    // still lists that id live, so the remote entity survives. The point here is only that it
    // must not surface as a user-facing conflict.
    const local = createSnapshot('desktop-a', { includeItemTombstone: true });
    local.tombstones[`bookmark-item|${COLLIDING_ID}`].deletedAt = T1;
    const remote = createSnapshot('phone-a', { includeLiveItem: true });
    remote.bookmarkItems[COLLIDING_ID].revision = 2;

    const result = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    });

    expect(result.conflicts).toEqual([]);
  });

  test('a tombstone whose revision is the older one still deletes, matching the App', () => {
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    local.bookmarkItems[COLLIDING_ID].revision = 5;
    const remote = createSnapshot('phone-a');
    remote.tombstones[`bookmark-item|${COLLIDING_ID}`] = tombstoneFor(COLLIDING_ID, 1);

    const result = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    });

    expect(result.conflicts).toEqual([]);
    expect(result.snapshot.bookmarkItems[COLLIDING_ID]).toBeUndefined();
  });

  test('an ordinary merge with a baseline still reports the same situation as a conflict', () => {
    // The no-baseline rule must not weaken the established three-way conflict contract:
    // ADR-0049 keeps deletion versus a concurrent incompatible field edit as a conflict.
    const baseline = createSnapshot('baseline', { includeLiveItem: true });
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    local.bookmarkItems[COLLIDING_ID].title = 'Desktop edit';
    local.bookmarkItems[COLLIDING_ID].revision = 2;
    const remote = createSnapshot('phone-a', { includeItemTombstone: true });

    const result = mergeLeafTabSyncSnapshot(baseline, local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    });

    expect(result.conflicts.map((conflict) => conflict.id)).toEqual([COLLIDING_ID]);
  });
});
