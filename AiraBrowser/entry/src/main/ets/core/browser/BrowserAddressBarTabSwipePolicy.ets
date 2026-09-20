import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabsOverviewSectionPolicy } from './tabsOverview/BrowserTabsOverviewSectionPolicy';

export type BrowserAddressBarTabSwipePhase = 'start' | 'update' | 'end' | 'cancel';

export interface BrowserAddressBarTabSwipeEvent {
  phase: BrowserAddressBarTabSwipePhase;
  offsetX: number;
  offsetY: number;
  velocityX: number;
}

export class BrowserAddressBarTabSwipePolicy {
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();

  resolveNeighbor(tabs: BrowserTabState[], activeTabId: string, offsetX: number): BrowserTabState | undefined {
    if (!Number.isFinite(offsetX) || offsetX === 0) {
      return undefined;
    }
    const sectionTabs = this.resolveSectionTabs(tabs, activeTabId);
    const index = sectionTabs.findIndex((tab: BrowserTabState) => tab.id === activeTabId);
    if (index < 0) {
      return undefined;
    }
    const neighborIndex = index + (offsetX < 0 ? 1 : -1);
    return neighborIndex >= 0 && neighborIndex < sectionTabs.length ? sectionTabs[neighborIndex] : undefined;
  }

  canStart(tabs: BrowserTabState[], activeTabId: string): boolean {
    return this.resolveSectionTabs(tabs, activeTabId).length > 1;
  }

  resolveOffset(offsetX: number, width: number, hasNeighbor: boolean): number {
    if (!Number.isFinite(offsetX) || !Number.isFinite(width) || width <= 0 || offsetX === 0) {
      return 0;
    }
    const distance = Math.abs(offsetX);
    // A progressively resistant edge stays below 48 vp even for extreme input.
    const magnitude = hasNeighbor ? Math.min(distance, width + 12) : 48 * (distance / (distance + 144));
    return offsetX < 0 ? -magnitude : magnitude;
  }

  shouldCommit(offsetX: number, velocityX: number, width: number, hasNeighbor: boolean): boolean {
    if (!hasNeighbor || !Number.isFinite(offsetX) || !Number.isFinite(width) || width <= 0 || offsetX === 0) {
      return false;
    }
    const velocity = Number.isFinite(velocityX) ? velocityX : 0;
    const sameDirection = (offsetX < 0 && velocity < 0) || (offsetX > 0 && velocity > 0);
    // A deliberate reversal wins over distance; small release noise does not.
    if (!sameDirection && Math.abs(velocity) >= 300) {
      return false;
    }
    return Math.abs(offsetX) >= width * 0.25 ||
      (Math.abs(offsetX) >= 24 && Math.abs(velocity) >= 650 && sameDirection);
  }

  resolveSettleDuration(offsetX: number, width: number, committed: boolean, reduceMotion: boolean): number {
    if (reduceMotion) {
      return 80;
    }
    const progress = Number.isFinite(offsetX) && Number.isFinite(width) && width > 0 ?
      Math.min(1, Math.abs(offsetX) / width) : 0;
    const remaining = committed ? 1 - progress : progress;
    return Math.round(220 + 80 * remaining);
  }

  private resolveSectionTabs(tabs: BrowserTabState[], activeTabId: string): BrowserTabState[] {
    const activeTab = tabs.find((tab: BrowserTabState) => tab.id === activeTabId);
    if (activeTab === undefined || activeTab.isHome) {
      return [];
    }
    return this.sectionPolicy.resolveTabsForSection(tabs, this.sectionPolicy.resolveSectionForTab(activeTab));
  }
}
