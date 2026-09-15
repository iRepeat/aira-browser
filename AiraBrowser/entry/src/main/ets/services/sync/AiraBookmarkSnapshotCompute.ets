import { BookmarkNode } from '../../common/models/BrowserModels';
import {
  AIRA_SYNC_ROOT_ORDER_KEY,
  AIRA_SYNC_SCHEMA_VERSION,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  isBookmarkRootNodeId,
  resolveBookmarkScope
} from '../../data/repositories/BookmarkRepositoryCore';

const AIRA_TOOLBAR_ROOT_ID = 'browser_root_toolbar';
const AIRA_OTHER_ROOT_ID = 'browser_root_other';
const AIRA_PRIVATE_TOOLBAR_ROOT_ID = 'aira_private_root_toolbar';
const AIRA_PRIVATE_OTHER_ROOT_ID = 'aira_private_root_other';
const LOCAL_CHROME_SYNC_ROOT_IDS: string[] = [
  BOOKMARK_TOOLBAR_ROOT_ID,
  BOOKMARK_OTHER_ROOT_ID
];
const PRIVATE_BOOKMARK_ROOT_IDS: string[] = [
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID
];

interface AiraOrderIdsByParent {
  orderKey: string;
  ids: string[];
}

interface AiraEntityMetadata {
  createdAt: string;
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

interface AiraBookmarkEntityIdPlan {
  idsByNodeId: Map<string, string>;
  parentEntityIdsByNodeId: Map<string, string | null>;
  occurrenceByNodeId: Map<string, number>;
  suppressedTombstoneNodeIds: Set<string>;
}

export interface AiraBookmarkSnapshotComputeResult {
  snapshot: AiraSyncSnapshot;
  originRepairs: BookmarkNode[];
}

interface AiraBookmarkDataSetComputeResult {
  dataSet: AiraSyncBookmarkDataSet;
  originRepairs: BookmarkNode[];
}

export class AiraBookmarkSnapshotCompute {
  buildFreshSnapshot(
    regularNodes: BookmarkNode[],
    privateNodes: BookmarkNode[],
    deviceId: string,
    generatedAt: string,
    previousSnapshot?: AiraSyncSnapshot | null
  ): AiraBookmarkSnapshotComputeResult {
    const regularResult = this.buildBookmarkDataSet(
      regularNodes,
      LOCAL_CHROME_SYNC_ROOT_IDS,
      generatedAt,
      deviceId,
      previousSnapshot
    );
    const privateResult = this.buildBookmarkDataSet(
      privateNodes,
      PRIVATE_BOOKMARK_ROOT_IDS,
      generatedAt,
      deviceId,
      previousSnapshot
    );
    return {
      snapshot: {
        meta: {
          version: AIRA_SYNC_SCHEMA_VERSION,
          deviceId: deviceId,
          generatedAt: generatedAt
        },
        bookmarkFolders: regularResult.dataSet.bookmarkFolders,
        bookmarkItems: regularResult.dataSet.bookmarkItems,
        bookmarkOrders: regularResult.dataSet.bookmarkOrders,
        tombstones: regularResult.dataSet.tombstones,
        appPrivateBookmarks: privateResult.dataSet
      },
      originRepairs: regularResult.originRepairs.concat(privateResult.originRepairs)
    };
  }

  private buildBookmarkDataSet(
    nodes: BookmarkNode[],
    rootIds: string[],
    generatedAt: string,
    deviceId: string,
    previousSnapshot?: AiraSyncSnapshot | null
  ): AiraBookmarkDataSetComputeResult {
    const syncNodeIds = this.buildScopedSyncNodeIdSet(nodes, rootIds);
    const reachableActiveNodes = this.filterReachableActiveNodes(nodes);
    const activeNodes = reachableActiveNodes.filter((node: BookmarkNode): boolean => syncNodeIds.has(node.id));
    const bookmarkFolders: AiraSyncBookmarkFolderEntity[] = [];
    const bookmarkItems: AiraSyncBookmarkItemEntity[] = [];
    const tombstones: AiraSyncTombstone[] = [];
    const entityIdPlan = this.buildBookmarkEntityIdPlan(nodes, true, previousSnapshot);
    const originRepairs = this.collectMissingOriginRepairs(nodes, entityIdPlan);
    const orderIdsByParent = this.buildOrderIdsByParent(activeNodes, entityIdPlan);
    const nodesByEntityId = this.buildNodesByPlannedEntityId(activeNodes, entityIdPlan);
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (syncNodeIds.has(node.id)) {
        this.appendBookmarkNodeEntity(node, entityIdPlan, bookmarkFolders, bookmarkItems, tombstones);
      }
    }
    const bookmarkOrders: AiraSyncBookmarkOrder[] = [];
    for (let index = 0; index < orderIdsByParent.length; index += 1) {
      bookmarkOrders.push(this.buildBookmarkOrderFromOrderEntry(
        orderIdsByParent[index],
        activeNodes,
        nodesByEntityId,
        generatedAt,
        deviceId
      ));
    }
    return {
      dataSet: {
        bookmarkFolders: bookmarkFolders,
        bookmarkItems: bookmarkItems,
        bookmarkOrders: bookmarkOrders,
        tombstones: this.canonicalizeTombstones(tombstones)
      },
      originRepairs: originRepairs
    };
  }

  private collectMissingOriginRepairs(
    nodes: BookmarkNode[],
    entityIdPlan: AiraBookmarkEntityIdPlan
  ): BookmarkNode[] {
    const repairedNodes: BookmarkNode[] = [];
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const existingOriginId = node.sync.originId?.trim() ?? '';
      if (!isBookmarkRootNodeId(node.id) && existingOriginId.length <= 0) {
        const plannedOriginId = entityIdPlan.idsByNodeId.get(node.id)?.trim() ?? '';
        if (plannedOriginId.length > 0) {
          repairedNodes.push({
            id: node.id,
            type: node.type,
            scope: resolveBookmarkScope(node.scope),
            parentId: node.parentId,
            title: node.title,
            url: node.url,
            position: node.position,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            sync: {
              state: node.sync.state,
              source: node.sync.source,
              lastModifiedAt: node.sync.lastModifiedAt,
              lastModifiedBy: node.sync.lastModifiedBy,
              deviceId: node.sync.deviceId,
              originId: plannedOriginId,
              deletedAt: node.sync.deletedAt
            }
          });
        }
      }
    }
    return repairedNodes;
  }

  private canonicalizeTombstones(tombstones: AiraSyncTombstone[]): AiraSyncTombstone[] {
    const latestByKey = new Map<string, AiraSyncTombstone>();
    tombstones.forEach((tombstone: AiraSyncTombstone): void => {
      const key = `${tombstone.type}|${tombstone.id}`;
      const current = latestByKey.get(key);
      if (current === undefined || this.isNewerTombstone(tombstone, current)) {
        latestByKey.set(key, tombstone);
      }
    });
    return Array.from(latestByKey.values());
  }

  private isNewerTombstone(candidate: AiraSyncTombstone, current: AiraSyncTombstone): boolean {
    const candidateDeletedAt = Date.parse(candidate.deletedAt);
    const currentDeletedAt = Date.parse(current.deletedAt);
    if (Number.isFinite(candidateDeletedAt) && Number.isFinite(currentDeletedAt) &&
      candidateDeletedAt !== currentDeletedAt) {
      return candidateDeletedAt > currentDeletedAt;
    }
    if (candidate.lastKnownRevision !== current.lastKnownRevision) {
      return candidate.lastKnownRevision > current.lastKnownRevision;
    }
    return candidate.deletedBy.localeCompare(current.deletedBy) > 0;
  }

  private appendBookmarkNodeEntity(
    node: BookmarkNode,
    entityIdPlan: AiraBookmarkEntityIdPlan,
    bookmarkFolders: AiraSyncBookmarkFolderEntity[],
    bookmarkItems: AiraSyncBookmarkItemEntity[],
    tombstones: AiraSyncTombstone[]
  ): void {
    const entityMetadata = this.createEntityMetadata(node);
    const entityId = this.resolvePlannedEntityId(node, entityIdPlan);
    const parentId = this.resolvePlannedParentEntityId(node, entityIdPlan);
    if (node.sync.deletedAt !== undefined) {
      if (entityIdPlan.suppressedTombstoneNodeIds.has(node.id)) {
        return;
      }
      tombstones.push({
        id: entityId,
        type: node.type === 'folder' ? 'bookmark-folder' : 'bookmark-item',
        deletedAt: this.toIsoString(node.sync.deletedAt ?? node.updatedAt),
        deletedBy: node.sync.lastModifiedBy,
        lastKnownRevision: entityMetadata.revision
      });
      return;
    }
    if (node.type === 'folder') {
      bookmarkFolders.push({
        id: entityId,
        type: 'bookmark-folder',
        parentId: parentId,
        title: node.title,
        createdAt: entityMetadata.createdAt,
        updatedAt: entityMetadata.updatedAt,
        updatedBy: entityMetadata.updatedBy,
        revision: entityMetadata.revision
      });
      return;
    }
    bookmarkItems.push({
      id: entityId,
      type: 'bookmark-item',
      parentId: parentId,
      title: node.title,
      url: node.url || '',
      createdAt: entityMetadata.createdAt,
      updatedAt: entityMetadata.updatedAt,
      updatedBy: entityMetadata.updatedBy,
      revision: entityMetadata.revision
    });
  }

  private buildBookmarkOrderFromOrderEntry(
    entry: AiraOrderIdsByParent,
    activeNodes: BookmarkNode[],
    nodesByEntityId: Map<string, BookmarkNode>,
    generatedAt: string,
    deviceId: string
  ): AiraSyncBookmarkOrder {
    const revisionSeedNode = this.findOrderRevisionSeed(activeNodes, nodesByEntityId, entry.orderKey, entry.ids);
    return {
      type: 'bookmark-order',
      parentId: entry.orderKey === AIRA_SYNC_ROOT_ORDER_KEY ? null : entry.orderKey,
      ids: entry.ids,
      updatedAt: revisionSeedNode ? this.toIsoString(revisionSeedNode.updatedAt) : generatedAt,
      updatedBy: revisionSeedNode ? revisionSeedNode.sync.lastModifiedBy : deviceId,
      revision: revisionSeedNode ? this.deriveRevision(revisionSeedNode) : 1
    };
  }

  private filterReachableActiveNodes(nodes: BookmarkNode[]): BookmarkNode[] {
    const nodesById = new Map<string, BookmarkNode>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    nodes.forEach((node: BookmarkNode) => {
      if (node.sync.deletedAt !== undefined) {
        return;
      }
      nodesById.set(node.id, node);
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
    });
    const reachableIds = new Set<string>();
    const roots = childrenByParent.get('') ?? [];
    roots.forEach((node: BookmarkNode) => {
      this.collectReachableActiveNodeIds(node.id, childrenByParent, reachableIds);
    });
    return nodes.filter((node: BookmarkNode) => {
      return node.sync.deletedAt === undefined && reachableIds.has(node.id) &&
        (node.parentId === undefined || nodesById.has(node.parentId));
    });
  }

  private buildScopedSyncNodeIdSet(nodes: BookmarkNode[], rootIds: string[]): Set<string> {
    const includedIds = new Set<string>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    nodes.forEach((node: BookmarkNode) => {
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
    });
    rootIds.forEach((rootId: string) => {
      this.collectChromeSyncNodeIds(rootId, childrenByParent, includedIds);
    });
    return includedIds;
  }

  private collectChromeSyncNodeIds(
    nodeId: string,
    childrenByParent: Map<string, BookmarkNode[]>,
    includedIds: Set<string>
  ): void {
    if (includedIds.has(nodeId)) {
      return;
    }
    includedIds.add(nodeId);
    const children = childrenByParent.get(nodeId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.collectChromeSyncNodeIds(child.id, childrenByParent, includedIds);
    });
  }

  private collectReachableActiveNodeIds(
    nodeId: string,
    childrenByParent: Map<string, BookmarkNode[]>,
    reachableIds: Set<string>
  ): void {
    if (reachableIds.has(nodeId)) {
      return;
    }
    reachableIds.add(nodeId);
    const children = childrenByParent.get(nodeId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.collectReachableActiveNodeIds(child.id, childrenByParent, reachableIds);
    });
  }

  private buildOrderIdsByParent(
    nodes: BookmarkNode[],
    entityIdPlan: AiraBookmarkEntityIdPlan
  ): AiraOrderIdsByParent[] {
    const nodesByOrderKey = new Map<string, BookmarkNode[]>();
    nodesByOrderKey.set(AIRA_SYNC_ROOT_ORDER_KEY, []);
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const parentId = this.resolvePlannedParentEntityId(node, entityIdPlan);
      const orderKey = parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : parentId;
      const siblings = nodesByOrderKey.get(orderKey) ?? [];
      siblings.push(node);
      nodesByOrderKey.set(orderKey, siblings);
    }
    const result: AiraOrderIdsByParent[] = [];
    const entries = Array.from(nodesByOrderKey.entries());
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex += 1) {
      const orderKey = entries[entryIndex][0];
      const siblings = entries[entryIndex][1].slice().sort((left: BookmarkNode, right: BookmarkNode) => {
        return left.position - right.position;
      });
      const ids: string[] = [];
      for (let index = 0; index < siblings.length; index += 1) {
        ids.push(this.resolvePlannedEntityId(siblings[index], entityIdPlan));
      }
      result.push({
        orderKey: orderKey,
        ids: ids
      });
    }
    return result;
  }

  private createEntityMetadata(node: BookmarkNode): AiraEntityMetadata {
    return {
      createdAt: this.toIsoString(node.createdAt),
      updatedAt: this.toIsoString(node.updatedAt),
      updatedBy: node.sync.lastModifiedBy,
      revision: this.deriveRevision(node)
    };
  }

  private deriveRevision(node: BookmarkNode): number {
    const syncFactor = node.sync.state === 'synced' ? 2 : node.sync.state === 'conflict' ? 3 : 1;
    return Math.max(1, syncFactor);
  }

  private normalizeParentId(node: BookmarkNode): string | null {
    if (node.parentId !== undefined) {
      return this.toAiraBookmarkEntityId(node.parentId);
    }
    if (node.id === BOOKMARK_TOOLBAR_ROOT_ID || node.id === BOOKMARK_OTHER_ROOT_ID) {
      return null;
    }
    if (node.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || node.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
      return null;
    }
    if (resolveBookmarkScope(node.scope) === 'private') {
      return AIRA_PRIVATE_OTHER_ROOT_ID;
    }
    return AIRA_OTHER_ROOT_ID;
  }

  private toAiraBookmarkEntityId(id: string): string {
    if (id === BOOKMARK_TOOLBAR_ROOT_ID) {
      return AIRA_TOOLBAR_ROOT_ID;
    }
    if (id === BOOKMARK_OTHER_ROOT_ID) {
      return AIRA_OTHER_ROOT_ID;
    }
    if (id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID) {
      return AIRA_PRIVATE_TOOLBAR_ROOT_ID;
    }
    if (id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
      return AIRA_PRIVATE_OTHER_ROOT_ID;
    }
    return id;
  }

  private buildBookmarkEntityIdPlan(
    nodes: BookmarkNode[],
    reuseExistingOriginId: boolean = true,
    previousSnapshot?: AiraSyncSnapshot | null
  ): AiraBookmarkEntityIdPlan {
    const idsByNodeId = new Map<string, string>();
    const parentEntityIdsByNodeId = new Map<string, string | null>();
    const occurrenceByNodeId = this.buildBookmarkEntityOccurrenceByNodeId(nodes);
    const usedEntityIds = new Set<string>();
    for (let index = 0; index < nodes.length; index += 1) {
      const originId = nodes[index].sync.originId?.trim() ?? '';
      if (originId.length > 0) {
        usedEntityIds.add(originId);
      }
    }
    const nodesById = new Map<string, BookmarkNode>();
    for (let index = 0; index < nodes.length; index += 1) {
      nodesById.set(nodes[index].id, nodes[index]);
    }
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      this.resolveBookmarkEntityIdForNode(
        node,
        nodesById,
        idsByNodeId,
        parentEntityIdsByNodeId,
        occurrenceByNodeId,
        reuseExistingOriginId,
        previousSnapshot,
        usedEntityIds
      );
      const plannedId = idsByNodeId.get(node.id);
      if (plannedId !== undefined) {
        usedEntityIds.add(plannedId);
      }
    }
    const suppressedTombstoneNodeIds = this.resolveBookmarkEntityIdCollisions(nodes, idsByNodeId);
    this.refreshPlannedParentEntityIds(nodes, idsByNodeId, parentEntityIdsByNodeId);
    return {
      idsByNodeId: idsByNodeId,
      parentEntityIdsByNodeId: parentEntityIdsByNodeId,
      occurrenceByNodeId: occurrenceByNodeId,
      suppressedTombstoneNodeIds: suppressedTombstoneNodeIds
    };
  }

  private resolveBookmarkEntityIdCollisions(
    nodes: BookmarkNode[],
    idsByNodeId: Map<string, string>
  ): Set<string> {
    const nodesByEntityId = new Map<string, BookmarkNode[]>();
    const reservedIds = new Set<string>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const entityId = idsByNodeId.get(node.id) ?? this.toAiraBookmarkEntityId(node.id);
      const collisions = nodesByEntityId.get(entityId) ?? [];
      collisions.push(node);
      nodesByEntityId.set(entityId, collisions);
      reservedIds.add(entityId);
    }
    const suppressedTombstoneNodeIds = new Set<string>();
    const entries = Array.from(nodesByEntityId.entries());
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex += 1) {
      const entityId = entries[entryIndex][0];
      const collisionNodes = entries[entryIndex][1];
      if (collisionNodes.length <= 1) {
        continue;
      }
      const liveNodes = collisionNodes
        .filter((node: BookmarkNode): boolean => node.sync.deletedAt === undefined)
        .sort((left: BookmarkNode, right: BookmarkNode): number => {
          return this.compareBookmarkEntityCollisionOwner(left, right, entityId);
        });
      if (liveNodes.length <= 0) {
        continue;
      }
      collisionNodes.forEach((node: BookmarkNode): void => {
        if (node.sync.deletedAt !== undefined) {
          suppressedTombstoneNodeIds.add(node.id);
        }
      });
      for (let liveIndex = 1; liveIndex < liveNodes.length; liveIndex += 1) {
        const node = liveNodes[liveIndex];
        idsByNodeId.set(node.id, this.createBookmarkEntityCollisionId(node, entityId, reservedIds));
      }
    }
    return suppressedTombstoneNodeIds;
  }

  private compareBookmarkEntityCollisionOwner(
    left: BookmarkNode,
    right: BookmarkNode,
    entityId: string
  ): number {
    const leftOwnsCanonicalRoot = isBookmarkRootNodeId(left.id) &&
      this.toAiraBookmarkEntityId(left.id) === entityId;
    const rightOwnsCanonicalRoot = isBookmarkRootNodeId(right.id) &&
      this.toAiraBookmarkEntityId(right.id) === entityId;
    if (leftOwnsCanonicalRoot !== rightOwnsCanonicalRoot) {
      return leftOwnsCanonicalRoot ? -1 : 1;
    }
    const leftOwnsOrigin = (left.sync.originId ?? '').trim() === entityId;
    const rightOwnsOrigin = (right.sync.originId ?? '').trim() === entityId;
    if (leftOwnsOrigin !== rightOwnsOrigin) {
      return leftOwnsOrigin ? -1 : 1;
    }
    if (left.updatedAt !== right.updatedAt) {
      return right.updatedAt - left.updatedAt;
    }
    return left.id.localeCompare(right.id);
  }

  private createBookmarkEntityCollisionId(
    node: BookmarkNode,
    entityId: string,
    reservedIds: Set<string>
  ): string {
    const prefix = node.type === 'folder' ? 'bkf_local_collision' : 'bkm_local_collision';
    const base = `${prefix}_${this.shortHash(`${entityId}|${node.type}|${node.id}`)}`;
    let candidate = base;
    let suffix = 1;
    while (reservedIds.has(candidate)) {
      candidate = `${base}_${suffix}`;
      suffix += 1;
    }
    reservedIds.add(candidate);
    return candidate;
  }

  private refreshPlannedParentEntityIds(
    nodes: BookmarkNode[],
    idsByNodeId: Map<string, string>,
    parentEntityIdsByNodeId: Map<string, string | null>
  ): void {
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.parentId !== undefined) {
        parentEntityIdsByNodeId.set(
          node.id,
          idsByNodeId.get(node.parentId) ?? this.toAiraBookmarkEntityId(node.parentId)
        );
      } else if (node.id === BOOKMARK_TOOLBAR_ROOT_ID || node.id === BOOKMARK_OTHER_ROOT_ID ||
        node.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || node.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
        parentEntityIdsByNodeId.set(node.id, null);
      } else {
        parentEntityIdsByNodeId.set(
          node.id,
          resolveBookmarkScope(node.scope) === 'private' ? AIRA_PRIVATE_OTHER_ROOT_ID : AIRA_OTHER_ROOT_ID
        );
      }
    }
  }

  private resolveBookmarkParentEntityId(
    node: BookmarkNode,
    nodesById: Map<string, BookmarkNode>,
    idsByNodeId: Map<string, string>,
    parentEntityIdsByNodeId: Map<string, string | null>,
    occurrenceByNodeId: Map<string, number>,
    reuseExistingOriginId: boolean,
    previousSnapshot?: AiraSyncSnapshot | null,
    usedEntityIds?: Set<string>
  ): string | null {
    if (node.parentId !== undefined) {
      const parentNode = nodesById.get(node.parentId);
      if (parentNode !== undefined) {
        return this.resolveBookmarkEntityIdForNode(
          parentNode,
          nodesById,
          idsByNodeId,
          parentEntityIdsByNodeId,
          occurrenceByNodeId,
          reuseExistingOriginId,
          previousSnapshot,
          usedEntityIds
        );
      }
      return this.toAiraBookmarkEntityId(node.parentId);
    }
    if (node.id === BOOKMARK_TOOLBAR_ROOT_ID || node.id === BOOKMARK_OTHER_ROOT_ID ||
      node.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || node.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
      return null;
    }
    if (resolveBookmarkScope(node.scope) === 'private') {
      return AIRA_PRIVATE_OTHER_ROOT_ID;
    }
    return AIRA_OTHER_ROOT_ID;
  }

  private resolveBookmarkEntityIdForNode(
    node: BookmarkNode,
    nodesById: Map<string, BookmarkNode>,
    idsByNodeId: Map<string, string>,
    parentEntityIdsByNodeId: Map<string, string | null>,
    occurrenceByNodeId: Map<string, number>,
    reuseExistingOriginId: boolean,
    previousSnapshot?: AiraSyncSnapshot | null,
    usedEntityIds?: Set<string>
  ): string {
    const existing = idsByNodeId.get(node.id);
    if (existing !== undefined) {
      return existing;
    }
    const parentEntityId = this.resolveBookmarkParentEntityId(
      node,
      nodesById,
      idsByNodeId,
      parentEntityIdsByNodeId,
      occurrenceByNodeId,
      reuseExistingOriginId,
      previousSnapshot,
      usedEntityIds
    );
    parentEntityIdsByNodeId.set(node.id, parentEntityId);
    const entityId = this.createBookmarkEntityId(
      node,
      parentEntityId,
      occurrenceByNodeId.get(node.id) ?? 1,
      reuseExistingOriginId,
      previousSnapshot,
      usedEntityIds
    );
    idsByNodeId.set(node.id, entityId);
    return entityId;
  }

  private createBookmarkEntityId(
    node: BookmarkNode,
    parentEntityId: string | null,
    occurrence: number,
    reuseExistingOriginId: boolean,
    previousSnapshot?: AiraSyncSnapshot | null,
    usedEntityIds?: Set<string>
  ): string {
    const rootEntityId = this.toAiraBookmarkEntityId(node.id);
    if (rootEntityId === AIRA_TOOLBAR_ROOT_ID || rootEntityId === AIRA_OTHER_ROOT_ID ||
      rootEntityId === AIRA_PRIVATE_TOOLBAR_ROOT_ID || rootEntityId === AIRA_PRIVATE_OTHER_ROOT_ID) {
      return rootEntityId;
    }
    if (reuseExistingOriginId) {
      const existingOriginId = node.sync.originId;
      if (existingOriginId !== undefined && existingOriginId.trim().length > 0 &&
        !this.isCanonicalBookmarkRootEntityId(existingOriginId.trim())) {
        return existingOriginId.trim();
      }
    }
    const legacyEntityId = this.resolveLegacyPreviousBookmarkEntityId(
      node,
      parentEntityId,
      occurrence,
      previousSnapshot,
      usedEntityIds ?? new Set<string>()
    );
    if (legacyEntityId !== undefined) {
      return legacyEntityId;
    }
    const parentEntityIdMatch = this.resolveUnusedPreviousBookmarkEntityId(
      node,
      parentEntityId,
      previousSnapshot,
      usedEntityIds ?? new Set<string>()
    );
    if (parentEntityIdMatch !== undefined) {
      return parentEntityIdMatch;
    }
    const previousEntityId = this.resolveUniquePreviousBookmarkEntityId(
      node,
      previousSnapshot,
      usedEntityIds ?? new Set<string>()
    );
    if (previousEntityId !== undefined) {
      return previousEntityId;
    }
    if (node.type === 'folder') {
      return this.createFolderEntityId(parentEntityId, node.title, occurrence);
    }
    return this.createItemEntityId(parentEntityId, node.title, node.url ?? '', occurrence);
  }

  private resolveLegacyPreviousBookmarkEntityId(
    node: BookmarkNode,
    parentEntityId: string | null,
    occurrence: number,
    previousSnapshot: AiraSyncSnapshot | null | undefined,
    usedEntityIds: Set<string>
  ): string | undefined {
    if (previousSnapshot === undefined || previousSnapshot === null) {
      return undefined;
    }
    const entityId = node.type === 'folder'
      ? this.createFolderEntityId(parentEntityId, node.title, occurrence)
      : this.createItemEntityId(parentEntityId, node.title, node.url ?? '', occurrence);
    if (usedEntityIds.has(entityId)) {
      return undefined;
    }
    let previousEntity: AiraSyncBookmarkFolderEntity | AiraSyncBookmarkItemEntity | undefined;
    if (resolveBookmarkScope(node.scope) === 'private') {
      const privateDataSet = previousSnapshot.appPrivateBookmarks;
      if (privateDataSet === undefined) {
        return undefined;
      }
      previousEntity = node.type === 'folder'
        ? privateDataSet.bookmarkFolders.find((folder: AiraSyncBookmarkFolderEntity): boolean => folder.id === entityId)
        : privateDataSet.bookmarkItems.find((item: AiraSyncBookmarkItemEntity): boolean => item.id === entityId);
    } else {
      previousEntity = node.type === 'folder'
        ? previousSnapshot.bookmarkFolders.find((folder: AiraSyncBookmarkFolderEntity): boolean => folder.id === entityId)
        : previousSnapshot.bookmarkItems.find((item: AiraSyncBookmarkItemEntity): boolean => item.id === entityId);
    }
    if (previousEntity === undefined || previousEntity.parentId !== parentEntityId ||
      previousEntity.title !== node.title) {
      return undefined;
    }
    if (node.type === 'bookmark' && (previousEntity as AiraSyncBookmarkItemEntity).url !== (node.url ?? '')) {
      return undefined;
    }
    return entityId;
  }

  private resolveUnusedPreviousBookmarkEntityId(
    node: BookmarkNode,
    parentEntityId: string | null,
    previousSnapshot: AiraSyncSnapshot | null | undefined,
    usedEntityIds: Set<string>
  ): string | undefined {
    if (previousSnapshot === undefined || previousSnapshot === null) {
      return undefined;
    }
    let folders: AiraSyncBookmarkFolderEntity[] = previousSnapshot.bookmarkFolders;
    let items: AiraSyncBookmarkItemEntity[] = previousSnapshot.bookmarkItems;
    if (resolveBookmarkScope(node.scope) === 'private') {
      const privateDataSet = previousSnapshot.appPrivateBookmarks;
      if (privateDataSet === undefined) {
        return undefined;
      }
      folders = privateDataSet.bookmarkFolders;
      items = privateDataSet.bookmarkItems;
    }
    if (node.type === 'folder') {
      const candidates = folders.filter((folder: AiraSyncBookmarkFolderEntity): boolean => {
        return folder.parentId === parentEntityId && folder.title === node.title && !usedEntityIds.has(folder.id);
      });
      return candidates.length === 1 ? candidates[0].id : undefined;
    }
    const nodeUrl = node.url ?? '';
    const candidates = items.filter((item: AiraSyncBookmarkItemEntity): boolean => {
      return item.parentId === parentEntityId && item.title === node.title && item.url === nodeUrl &&
        !usedEntityIds.has(item.id);
    });
    return candidates.length === 1 ? candidates[0].id : undefined;
  }

  private resolveUniquePreviousBookmarkEntityId(
    node: BookmarkNode,
    previousSnapshot: AiraSyncSnapshot | null | undefined,
    usedEntityIds: Set<string>
  ): string | undefined {
    if (previousSnapshot === undefined || previousSnapshot === null) {
      return undefined;
    }
    let previousFolders: AiraSyncBookmarkFolderEntity[] = previousSnapshot.bookmarkFolders;
    let previousItems: AiraSyncBookmarkItemEntity[] = previousSnapshot.bookmarkItems;
    if (resolveBookmarkScope(node.scope) === 'private') {
      if (previousSnapshot.appPrivateBookmarks === undefined) {
        return undefined;
      }
      previousFolders = previousSnapshot.appPrivateBookmarks.bookmarkFolders;
      previousItems = previousSnapshot.appPrivateBookmarks.bookmarkItems;
    }
    if (node.type === 'folder') {
      const candidates = previousFolders
        .filter((folder: AiraSyncBookmarkFolderEntity): boolean => folder.title === node.title)
        .map((folder: AiraSyncBookmarkFolderEntity): string => folder.id);
      return candidates.length === 1 && !usedEntityIds.has(candidates[0]) ? candidates[0] : undefined;
    }
    const nodeUrl = node.url ?? '';
    const candidates = previousItems
      .filter((item: AiraSyncBookmarkItemEntity): boolean => item.title === node.title && item.url === nodeUrl)
      .map((item: AiraSyncBookmarkItemEntity): string => item.id);
    return candidates.length === 1 && !usedEntityIds.has(candidates[0]) ? candidates[0] : undefined;
  }

  private isCanonicalBookmarkRootEntityId(id: string): boolean {
    return id === AIRA_TOOLBAR_ROOT_ID || id === AIRA_OTHER_ROOT_ID ||
      id === AIRA_PRIVATE_TOOLBAR_ROOT_ID || id === AIRA_PRIVATE_OTHER_ROOT_ID;
  }

  private buildBookmarkEntityOccurrenceByNodeId(nodes: BookmarkNode[]): Map<string, number> {
    const occurrenceByNodeId = new Map<string, number>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const parentKey = node.parentId ?? '';
      const siblings = childrenByParent.get(parentKey) ?? [];
      siblings.push(node);
      childrenByParent.set(parentKey, siblings);
    }
    const siblingGroups = Array.from(childrenByParent.values());
    for (let groupIndex = 0; groupIndex < siblingGroups.length; groupIndex += 1) {
      const siblings = siblingGroups[groupIndex].slice().sort((left: BookmarkNode, right: BookmarkNode) => {
        return left.position - right.position;
      });
      const occurrenceBySignature = new Map<string, number>();
      for (let index = 0; index < siblings.length; index += 1) {
        const node = siblings[index];
        const signature = this.buildBookmarkEntityOccurrenceSignature(node);
        const occurrence = (occurrenceBySignature.get(signature) ?? 0) + 1;
        occurrenceBySignature.set(signature, occurrence);
        occurrenceByNodeId.set(node.id, occurrence);
      }
    }
    return occurrenceByNodeId;
  }

  private buildBookmarkEntityOccurrenceSignature(node: BookmarkNode): string {
    if (node.type === 'folder') {
      return `folder:${node.title}`;
    }
    return `bookmark:${node.title}:${node.url ?? ''}`;
  }

  private createFolderEntityId(parentId: string | null, title: string, occurrence: number): string {
    return `bkf_${this.slugify(title || 'folder')}_${this.shortHash(`${parentId || AIRA_SYNC_ROOT_ORDER_KEY}|${title}|${occurrence}`)}`;
  }

  private createItemEntityId(parentId: string | null, title: string, url: string, occurrence: number): string {
    return `bkm_${this.slugify(title || url || 'item')}_${this.shortHash(`${parentId || AIRA_SYNC_ROOT_ORDER_KEY}|${title}|${url}|${occurrence}`)}`;
  }

  private resolvePlannedEntityId(node: BookmarkNode, plan: AiraBookmarkEntityIdPlan): string {
    return plan.idsByNodeId.get(node.id) ?? this.toAiraBookmarkEntityId(node.id);
  }

  private resolvePlannedParentEntityId(node: BookmarkNode, plan: AiraBookmarkEntityIdPlan): string | null {
    return plan.parentEntityIdsByNodeId.get(node.id) ?? this.normalizeParentId(node);
  }

  private slugify(value: string): string {
    const lower = (value || '').toLowerCase();
    let result = '';
    let previousDash = false;
    for (let index = 0; index < lower.length && result.length < 32; index += 1) {
      const code = lower.charCodeAt(index);
      const isAlphaNumber = (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
      if (isAlphaNumber) {
        result += lower.charAt(index);
        previousDash = false;
      } else if (!previousDash && result.length > 0) {
        result += '-';
        previousDash = true;
      }
    }
    while (result.endsWith('-')) {
      result = result.slice(0, result.length - 1);
    }
    return result.length > 0 ? result : 'bookmark';
  }

  private shortHash(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36);
  }

  private toIsoString(timestamp: number): string {
    return new Date(timestamp).toISOString();
  }

  private findOrderRevisionSeed(
    nodes: BookmarkNode[],
    nodesByEntityId: Map<string, BookmarkNode>,
    orderKey: string,
    ids: string[]
  ): BookmarkNode | undefined {
    const seedId = ids[0];
    if (seedId !== undefined) {
      return nodesByEntityId.get(seedId);
    }
    if (orderKey === AIRA_SYNC_ROOT_ORDER_KEY) {
      return nodes.find((node: BookmarkNode) => node.parentId === undefined);
    }
    return nodesByEntityId.get(orderKey);
  }

  private buildNodesByPlannedEntityId(
    nodes: BookmarkNode[],
    entityIdPlan: AiraBookmarkEntityIdPlan
  ): Map<string, BookmarkNode> {
    const result = new Map<string, BookmarkNode>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const entityId = this.resolvePlannedEntityId(node, entityIdPlan);
      if (!result.has(entityId)) {
        result.set(entityId, node);
      }
    }
    return result;
  }
}
