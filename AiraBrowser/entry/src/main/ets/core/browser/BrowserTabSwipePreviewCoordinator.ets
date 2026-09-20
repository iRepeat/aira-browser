import { image } from '@kit.ImageKit';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabPreviewState } from './BrowserTabPreviewCoordinator';

export interface BrowserTabSwipePreviewImage {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

export interface BrowserTabSwipePreviewFacts {
  windowId: string;
  tabs: BrowserTabState[];
  activeTabId: string;
  canCapture: boolean;
  motionActive: boolean;
  // Shell root dimensions, unaffected by the active page's bottom reservation.
  viewportWidth: number;
  viewportHeight: number;
}

export interface BrowserTabSwipePreviewHost {
  readFacts: () => BrowserTabSwipePreviewFacts;
  getHostedGeneration: (tabId: string) => number;
  capture: (tabId: string) => Promise<BrowserTabSwipePreviewImage | undefined>;
  release: (pixelMap: image.PixelMap) => void;
  afterFrame: (callback: () => void) => void;
  notifyChanged: () => void;
}

interface SwipePreviewIdentity {
  tabId: string;
  signature: string;
  ephemeral: boolean;
  scrollRevision: number;
}

interface SwipePreviewCaptureIdentity extends SwipePreviewIdentity {
  generation: number;
}

interface SwipePreviewEntry {
  identity: SwipePreviewCaptureIdentity;
  state: BrowserTabPreviewState;
  pixelMap: image.PixelMap;
  bytes: number;
  used: number;
}

interface SwipePreviewRun {
  identity: SwipePreviewCaptureIdentity;
  valid: boolean;
  task: Promise<boolean>;
}

interface SwipePreviewPendingUnpin {
  generation: number;
  frames: number;
}

const MAX_ENTRIES: number = 8;
const MAX_BYTES: number = 32 * 1024 * 1024;

// Owns only independently captured, in-memory swipe images. No overview/cache-store access.
export class BrowserTabSwipePreviewCoordinator {
  private host: BrowserTabSwipePreviewHost;
  private windowId?: string;
  private entries: Map<string, SwipePreviewEntry> = new Map();
  private runs: Map<string, SwipePreviewRun> = new Map();
  private pins: Map<string, number> = new Map();
  private pendingUnpins: Map<string, SwipePreviewPendingUnpin> = new Map();
  private retired: SwipePreviewEntry[] = [];
  private releasing: SwipePreviewEntry[] = [];
  private documents: Map<string, number> = new Map();
  private scrolls: Map<string, number> = new Map();
  private ephemeralTabs: Set<string> = new Set();
  private pendingTimer: number = -1;
  private pendingIdentity?: SwipePreviewCaptureIdentity;
  private unpinGeneration: number = 0;
  private disposed: boolean = false;
  private clock: number = 0;

  constructor(host: BrowserTabSwipePreviewHost) {
    this.host = host;
  }

  getPreviewState(tabId: string): BrowserTabPreviewState | undefined {
    const entry = this.entries.get(tabId);
    const identity = this.identity(tabId, this.host.readFacts());
    if (entry === undefined || identity === undefined || entry.identity.signature !== identity.signature) {
      return undefined;
    }
    return entry.state;
  }

  schedule(delayMs: number = 250): void {
    this.reconcile();
    this.cancelPending();
    const facts = this.host.readFacts();
    if (facts.motionActive || !facts.canCapture) {
      return;
    }
    const identity = this.captureIdentity(facts.activeTabId, facts);
    if (identity === undefined) {
      return;
    }
    this.pendingIdentity = identity;
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1;
      this.pendingIdentity = undefined;
      const current = this.host.readFacts();
      if (!current.motionActive && this.captureMatches(identity, current)) {
        this.captureActive();
      }
    }, Math.max(0, delayMs));
  }

  handleScroll(tabId: string): void {
    this.trackEphemeral(tabId);
    this.scrolls.set(tabId, (this.scrolls.get(tabId) ?? 0) + 1);
    this.cancelRun(tabId);
    if (this.pendingIdentity?.tabId === tabId) {
      this.cancelPending();
    }
    const facts = this.host.readFacts();
    if (facts.activeTabId === tabId && !facts.motionActive) {
      this.schedule(200);
    }
  }

  captureActive(): Promise<boolean> {
    this.reconcile();
    const facts = this.host.readFacts();
    const identity = this.captureIdentity(facts.activeTabId, facts);
    if (!facts.canCapture || identity === undefined) {
      return Promise.resolve(false);
    }
    const existing = this.runs.get(identity.tabId);
    if (existing !== undefined && existing.valid && this.sameCapture(existing.identity, identity)) {
      return existing.task;
    }
    this.cancelRun(identity.tabId);
    const run: SwipePreviewRun = { identity: identity, valid: true, task: Promise.resolve(false) };
    this.runs.set(identity.tabId, run);
    run.task = this.performCapture(run);
    return run.task;
  }

  noteDocumentBegin(tabId: string): void {
    this.trackEphemeral(tabId);
    this.documents.set(tabId, (this.documents.get(tabId) ?? 0) + 1);
    this.cancelRun(tabId);
    if (this.pendingIdentity?.tabId === tabId) {
      this.cancelPending();
    }
    this.removeEntry(tabId);
    this.notify();
  }

  pin(tabId: string): void {
    if (this.disposed) {
      return;
    }
    if (this.pendingUnpins.has(tabId)) {
      // Transfer the deferred final pin to the new gesture. Old frame callbacks
      // remain harmless through the generation/token check.
      this.pendingUnpins.delete(tabId);
      return;
    }
    this.pins.set(tabId, (this.pins.get(tabId) ?? 0) + 1);
  }

  unpin(tabId: string): void {
    if (this.disposed) {
      return;
    }
    const count = this.pins.get(tabId) ?? 0;
    if (count === 0 || this.pendingUnpins.has(tabId)) {
      return;
    }
    if (count > 1) {
      this.pins.set(tabId, count - 1);
      return;
    }
    const pending: SwipePreviewPendingUnpin = { generation: ++this.unpinGeneration, frames: 0 };
    this.pendingUnpins.set(tabId, pending);
    this.host.afterFrame(() => this.finishUnpinFrame(tabId, pending));
  }

  reconcile(): void {
    const facts = this.host.readFacts();
    if (this.windowId === undefined) {
      this.windowId = facts.windowId;
    }
    if (facts.windowId !== this.windowId) {
      this.clear();
      this.windowId = facts.windowId;
      return;
    }
    const liveIds: Set<string> = new Set(facts.tabs.map((tab: BrowserTabState) => tab.id));
    this.documents.forEach((revision: number, tabId: string) => {
      if (!liveIds.has(tabId)) {
        this.documents.delete(tabId);
      }
    });
    this.scrolls.forEach((revision: number, tabId: string) => {
      if (!liveIds.has(tabId)) {
        this.scrolls.delete(tabId);
      }
    });
    this.ephemeralTabs.forEach((tabId: string) => {
      if (!liveIds.has(tabId)) {
        this.ephemeralTabs.delete(tabId);
      }
    });
    const stale: string[] = [];
    this.entries.forEach((entry: SwipePreviewEntry, tabId: string) => {
      const identity = this.identity(tabId, facts);
      if (identity === undefined || identity.signature !== entry.identity.signature) {
        stale.push(tabId);
      }
    });
    stale.forEach((tabId: string) => this.removeEntry(tabId));
    this.runs.forEach((run: SwipePreviewRun, tabId: string) => {
      if (!this.captureMatches(run.identity, facts)) {
        this.cancelRun(tabId);
      }
    });
    if (this.pendingIdentity !== undefined && !this.captureMatches(this.pendingIdentity, facts)) {
      this.cancelPending();
    }
    if (stale.length > 0) {
      this.notify();
    }
  }

  suspend(): void {
    this.cancelPending();
    this.runs.forEach((run: SwipePreviewRun) => { run.valid = false; });
    this.runs.clear();
  }

  clear(): void {
    this.suspend();
    const ids: string[] = [];
    this.entries.forEach((entry: SwipePreviewEntry, tabId: string) => { ids.push(tabId); });
    ids.forEach((tabId: string) => this.removeEntry(tabId));
    this.documents.clear();
    this.scrolls.clear();
    this.ephemeralTabs.clear();
    this.notify();
  }

  clearEphemeral(): void {
    const ids: Set<string> = new Set(this.ephemeralTabs);
    this.host.readFacts().tabs.forEach((tab: BrowserTabState) => {
      if (tab.privacyMode === 'private' || tab.dataScope === 'session_ephemeral') {
        ids.add(tab.id);
      }
    });
    if (this.pendingIdentity?.ephemeral) {
      ids.add(this.pendingIdentity.tabId);
    }
    this.runs.forEach((run: SwipePreviewRun, tabId: string) => {
      if (run.identity.ephemeral) {
        ids.add(tabId);
      }
    });
    this.entries.forEach((entry: SwipePreviewEntry, tabId: string) => {
      if (entry.identity.ephemeral) {
        ids.add(tabId);
      }
    });
    ids.forEach((tabId: string) => {
      if (this.pendingIdentity?.tabId === tabId) {
        this.cancelPending();
      }
      this.cancelRun(tabId);
      this.removeEntry(tabId);
      this.documents.delete(tabId);
      this.scrolls.delete(tabId);
      this.ephemeralTabs.delete(tabId);
    });
    this.notify();
  }

  /** Call only after the UI consumer has been removed from the shell. */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.cancelPending();
    this.runs.forEach((run: SwipePreviewRun) => { run.valid = false; });
    this.runs.clear();
    this.unpinGeneration++;
    this.pendingUnpins.clear();
    this.pins.clear();
    const owned: SwipePreviewEntry[] = [];
    this.entries.forEach((entry: SwipePreviewEntry) => { owned.push(entry); });
    owned.push(...this.retired, ...this.releasing);
    this.entries.clear();
    this.retired = [];
    this.releasing = [];
    owned.forEach((entry: SwipePreviewEntry) => this.release(entry.pixelMap));
  }

  private finishUnpinFrame(tabId: string, pending: SwipePreviewPendingUnpin): void {
    const current = this.pendingUnpins.get(tabId);
    if (this.disposed || current !== pending || current.generation !== pending.generation) {
      return;
    }
    current.frames++;
    if (current.frames < 2) {
      this.host.afterFrame(() => this.finishUnpinFrame(tabId, pending));
      return;
    }
    this.pendingUnpins.delete(tabId);
    this.pins.delete(tabId);
    const released = this.retired.filter((entry: SwipePreviewEntry) => entry.identity.tabId === tabId);
    this.retired = this.retired.filter((entry: SwipePreviewEntry) => entry.identity.tabId !== tabId);
    released.forEach((entry: SwipePreviewEntry) => { this.releasing.push(entry); });
    released.forEach((entry: SwipePreviewEntry) => {
      const index = this.releasing.indexOf(entry);
      if (index >= 0) {
        this.release(entry.pixelMap);
        this.releasing.splice(index, 1);
      }
    });
  }

  private identity(tabId: string, facts: BrowserTabSwipePreviewFacts): SwipePreviewIdentity | undefined {
    const tab = facts.tabs.find((candidate: BrowserTabState) => candidate.id === tabId);
    if (tab === undefined || tab.isHome || !Number.isFinite(facts.viewportWidth) ||
      !Number.isFinite(facts.viewportHeight) || facts.viewportWidth <= 0 || facts.viewportHeight <= 0) {
      return undefined;
    }
    return {
      tabId: tabId,
      signature: JSON.stringify([facts.windowId, tabId, tab.profileId, tab.privacyMode, tab.dataScope,
        tab.url, (this.documents.get(tabId) ?? 0).toString(),
        facts.viewportWidth.toString(), facts.viewportHeight.toString()]),
      ephemeral: tab.privacyMode === 'private' || tab.dataScope === 'session_ephemeral',
      scrollRevision: this.scrolls.get(tabId) ?? 0
    };
  }

  private trackEphemeral(tabId: string): void {
    const tab = this.host.readFacts().tabs.find((candidate: BrowserTabState) => candidate.id === tabId);
    if (tab !== undefined && (tab.privacyMode === 'private' || tab.dataScope === 'session_ephemeral')) {
      this.ephemeralTabs.add(tabId);
    }
  }

  private captureIdentity(tabId: string, facts: BrowserTabSwipePreviewFacts):
    SwipePreviewCaptureIdentity | undefined {
    const identity = this.identity(tabId, facts);
    if (identity === undefined) {
      return undefined;
    }
    return {
      tabId: identity.tabId, signature: identity.signature, ephemeral: identity.ephemeral,
      scrollRevision: identity.scrollRevision, generation: this.host.getHostedGeneration(tabId)
    };
  }

  private sameCapture(left: SwipePreviewCaptureIdentity, right: SwipePreviewCaptureIdentity): boolean {
    return left.signature === right.signature && left.scrollRevision === right.scrollRevision &&
      left.generation === right.generation;
  }

  private captureMatches(identity: SwipePreviewCaptureIdentity, facts: BrowserTabSwipePreviewFacts): boolean {
    const current = this.captureIdentity(identity.tabId, facts);
    return facts.canCapture && facts.activeTabId === identity.tabId && current !== undefined &&
      this.sameCapture(identity, current);
  }

  private async performCapture(run: SwipePreviewRun): Promise<boolean> {
    let captured: BrowserTabSwipePreviewImage | undefined = undefined;
    try {
      if (!run.valid || !this.captureMatches(run.identity, this.host.readFacts())) {
        return false;
      }
      captured = await this.host.capture(run.identity.tabId);
      if (captured === undefined || !run.valid || this.runs.get(run.identity.tabId) !== run ||
        !this.captureMatches(run.identity, this.host.readFacts()) || this.pins.has(run.identity.tabId)) {
        return false;
      }
      const bytes = captured.width * captured.height * 4;
      if (!Number.isFinite(bytes) || captured.width <= 0 || captured.height <= 0 || bytes > MAX_BYTES) {
        return false;
      }
      if (!this.makeRoom(run.identity.tabId, bytes)) {
        return false;
      }
      this.removeEntry(run.identity.tabId);
      const state: BrowserTabPreviewState = {
        tabId: run.identity.tabId,
        sharedSnapshotPixelMap: captured.pixelMap,
        sharedSnapshotImageWidth: captured.width,
        sharedSnapshotImageHeight: captured.height,
        capturedAt: Date.now(),
        transitionSource: { captureSource: 'component', captureScope: 'web-content', transitionFrame: 'current-web' }
      };
      const entry: SwipePreviewEntry = {
        identity: run.identity, state: state, pixelMap: captured.pixelMap, bytes: bytes, used: ++this.clock
      };
      this.entries.set(run.identity.tabId, entry);
      captured = undefined; // Ownership transferred; even a throwing notification cannot release the cached image.
      this.notify();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (captured !== undefined) {
        this.release(captured.pixelMap);
      }
      if (this.runs.get(run.identity.tabId) === run) {
        this.runs.delete(run.identity.tabId);
      }
    }
  }

  private makeRoom(tabId: string, bytes: number): boolean {
    let total = bytes;
    let count = 1;
    this.retired.forEach((entry: SwipePreviewEntry) => { total += entry.bytes; count++; });
    this.releasing.forEach((entry: SwipePreviewEntry) => { total += entry.bytes; count++; });
    const candidates: SwipePreviewEntry[] = [];
    this.entries.forEach((entry: SwipePreviewEntry, id: string) => {
      if (id !== tabId) {
        total += entry.bytes;
        count++;
        if (!this.pins.has(id)) {
          candidates.push(entry);
        }
      }
    });
    candidates.sort((left: SwipePreviewEntry, right: SwipePreviewEntry) => left.used - right.used);
    for (const entry of candidates) {
      if (total <= MAX_BYTES && count <= MAX_ENTRIES) {
        break;
      }
      this.removeEntry(entry.identity.tabId);
      total -= entry.bytes;
      count--;
    }
    return total <= MAX_BYTES && count <= MAX_ENTRIES;
  }

  private removeEntry(tabId: string): void {
    const entry = this.entries.get(tabId);
    if (entry === undefined) {
      return;
    }
    this.entries.delete(tabId);
    if (this.pins.has(tabId)) {
      this.retired.push(entry);
    } else {
      this.release(entry.pixelMap);
    }
  }

  private cancelPending(): void {
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
    }
    this.pendingTimer = -1;
    this.pendingIdentity = undefined;
  }

  private cancelRun(tabId: string): void {
    const run = this.runs.get(tabId);
    if (run !== undefined) {
      run.valid = false;
      this.runs.delete(tabId);
    }
  }

  private release(pixelMap: image.PixelMap): void {
    try {
      this.host.release(pixelMap);
    } catch (_) {
      // The owner calls release exactly once, including when the platform throws.
    }
  }

  private notify(): void {
    try {
      this.host.notifyChanged();
    } catch (_) {
      // UI notification failures do not change image ownership.
    }
  }
}
