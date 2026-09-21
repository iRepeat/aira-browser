import { BROWSER_TAB_PREVIEW_CARD_HEIGHT_RATIO } from './BrowserTabPreviewMetrics';
import { BrowserTabsOverviewLayoutStyle } from '../../common/models/BrowserModels';
import {
  AppWindowResponsiveFacts,
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';
import {
  BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT,
  BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP
} from './BrowserTabsOverviewVisualTokens';

export interface BrowserTabsOverviewLayoutInput {
  gridWidth: number;
  sheetWidth: number;
  sheetHeight: number;
  layoutStyle?: BrowserTabsOverviewLayoutStyle | string;
}

export interface BrowserTabsOverviewHorizontalCardFrameInput {
  maxWidth: number;
  maxHeight: number;
  snapshotWidth: number;
  snapshotHeight: number;
}

export interface BrowserTabsOverviewHorizontalCardFrame {
  width: number;
  height: number;
}

export interface BrowserTabsOverviewLayoutState {
  layoutStyle: BrowserTabsOverviewLayoutStyle;
  columnCount: number;
  columnsTemplate: string;
  gridGap: number;
  cardWidth: number;
  previewHeight: number;
  identityHeaderHeight: number;
  identityPreviewGap: number;
  itemHeight: number;
  horizontalContentInset: number;
}

export function isSameTabsOverviewLayoutState(
  current: BrowserTabsOverviewLayoutState,
  next: BrowserTabsOverviewLayoutState
): boolean {
  return current.layoutStyle === next.layoutStyle &&
    current.columnCount === next.columnCount &&
    current.columnsTemplate === next.columnsTemplate &&
    current.gridGap === next.gridGap &&
    current.cardWidth === next.cardWidth &&
    current.previewHeight === next.previewHeight &&
    current.identityHeaderHeight === next.identityHeaderHeight &&
    current.identityPreviewGap === next.identityPreviewGap &&
    current.itemHeight === next.itemHeight &&
    current.horizontalContentInset === next.horizontalContentInset;
}

interface BrowserTabsOverviewLayoutBaseState {
  layoutStyle: BrowserTabsOverviewLayoutStyle;
  columnCount: number;
  columnsTemplate: string;
  gridGap: number;
  cardWidth: number;
  previewHeight: number;
  horizontalContentInset: number;
}

const TAB_OVERVIEW_LAYOUT_MIN_CARD_WIDTH: number = 132;
const TAB_OVERVIEW_LAYOUT_MIN_PREVIEW_HEIGHT: number = 118;
const TAB_OVERVIEW_LAYOUT_MAX_PORTRAIT_PREVIEW_HEIGHT: number = 360;
const TAB_OVERVIEW_LAYOUT_PHONE_LANDSCAPE_PREVIEW_RATIO: number = 0.58;
const TAB_OVERVIEW_LAYOUT_TABLET_LANDSCAPE_PREVIEW_RATIO: number = 0.62;
const TAB_OVERVIEW_LAYOUT_PORTRAIT_PREVIEW_RATIO: number = BROWSER_TAB_PREVIEW_CARD_HEIGHT_RATIO;
const TAB_OVERVIEW_LAYOUT_PREVIEW_HEIGHT_MULTIPLIER: number = 1.08;
const TAB_OVERVIEW_LAYOUT_GRID_GAP: number = 16;
const TAB_OVERVIEW_LAYOUT_TOP_PADDING: number = 16;
const TAB_OVERVIEW_LAYOUT_TOP_SAFE_GAP: number = 10;
/**
 * Zero gap for the stacked deck.
 *
 * Every card is placed by its own offset inside a `Stack`, so there is no stride left for a gap to
 * sit in. The value only reaches the selection-displacement camera now, where a card travels its
 * own width and nothing more.
 */
const TAB_OVERVIEW_STACK_GAP: number = 0;
/**
 * Gap between the large cards of the horizontal strip.
 */
const TAB_OVERVIEW_HORIZONTAL_CARDS_GAP: number = 18;
/**
 * Focused card width, over the usable width, for the stacked deck on a portrait window.
 *
 * Smaller than the flat strip's 0.82 because a deck spends width on the leading strip and on the
 * trailing neighbour instead of on the focused card alone. Kept at 0.70 so the nearest leading
 * strip, which peeks `cardWidth * 0.22` past the focused card's edge, stays on the sheet on the
 * narrowest phones.
 */
const TAB_OVERVIEW_STACK_PHONE_WIDTH_RATIO: number = 0.70;
const TAB_OVERVIEW_STACK_LANDSCAPE_WIDTH_RATIO: number = 0.56;
const TAB_OVERVIEW_STACK_MAX_WIDTH: number = 520;
const TAB_OVERVIEW_STACK_MIN_WIDTH: number = 200;
const TAB_OVERVIEW_STACK_VIEWPORT_HEIGHT_RATIO: number = 0.66;
const TAB_OVERVIEW_STACK_MIN_HEIGHT: number = 180;
/**
 * Portrait width ratio of one large card in the horizontal strip.
 *
 * 0.82 leaves the neighbouring card a sliver of the sheet, which is what makes the strip read as
 * "swipe sideways for the next card" instead of "one card fills the screen".
 */
const TAB_OVERVIEW_HORIZONTAL_CARDS_PHONE_WIDTH_RATIO: number = 0.82;
const TAB_OVERVIEW_HORIZONTAL_CARDS_LANDSCAPE_WIDTH_RATIO: number = 0.56;
const TAB_OVERVIEW_HORIZONTAL_CARDS_MAX_WIDTH: number = 520;
const TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_WIDTH: number = 220;
const TAB_OVERVIEW_HORIZONTAL_CARDS_VIEWPORT_HEIGHT_RATIO: number = 0.66;
const TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_HEIGHT: number = 180;

export class BrowserTabsOverviewLayoutViewModel {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  buildState(input: BrowserTabsOverviewLayoutInput): BrowserTabsOverviewLayoutState {
    const layoutStyle = this.normalizeLayoutStyle(input.layoutStyle);
    const usableWidth = this.resolveUsableWidth(input);
    if (layoutStyle === 'horizontal_cards') {
      return this.buildHorizontalCardsState(input, usableWidth);
    }
    if (layoutStyle === 'stack') {
      return this.buildStackState(input, usableWidth);
    }
    const responsiveFacts = this.resolveResponsiveFacts(input);
    const columnCount = this.resolveColumnCount(responsiveFacts);
    const cardWidth = this.resolveCardWidth(usableWidth, columnCount);
    const previewHeight = this.resolvePreviewHeight(input, cardWidth);
    return this.buildLayoutState({
      layoutStyle: 'grid',
      columnCount: columnCount,
      columnsTemplate: this.buildColumnsTemplate(columnCount),
      gridGap: TAB_OVERVIEW_LAYOUT_GRID_GAP,
      cardWidth: cardWidth,
      previewHeight: previewHeight,
      horizontalContentInset: 0
    });
  }

  /**
   * The large centred card strip.
   *
   * One card per page, centred by an equal inset on either edge so the first and the last card can
   * both rest in the middle of the sheet.
   */
  private buildHorizontalCardsState(
    input: BrowserTabsOverviewLayoutInput,
    usableWidth: number
  ): BrowserTabsOverviewLayoutState {
    const cardWidth = this.resolveHorizontalCardWidth(input, usableWidth);
    return this.buildLayoutState({
      layoutStyle: 'horizontal_cards',
      columnCount: 1,
      columnsTemplate: '1fr',
      gridGap: TAB_OVERVIEW_HORIZONTAL_CARDS_GAP,
      cardWidth: cardWidth,
      previewHeight: this.resolveHorizontalPreviewHeight(input),
      horizontalContentInset: Math.max(0, (usableWidth - cardWidth) / 2)
    });
  }

  /**
   * The stacked deck.
   *
   * Every card is placed by its own offset inside a `Stack`, so the state only carries the focused
   * card's width and the preview height the deck scales from.
   */
  private buildStackState(
    input: BrowserTabsOverviewLayoutInput,
    usableWidth: number
  ): BrowserTabsOverviewLayoutState {
    const cardWidth = this.resolveStackCardWidth(input, usableWidth);
    return this.buildLayoutState({
      layoutStyle: 'stack',
      columnCount: 1,
      columnsTemplate: '1fr',
      gridGap: TAB_OVERVIEW_STACK_GAP,
      cardWidth: cardWidth,
      previewHeight: this.resolveStackPreviewHeight(input),
      horizontalContentInset: 0
    });
  }

  private buildLayoutState(base: BrowserTabsOverviewLayoutBaseState): BrowserTabsOverviewLayoutState {
    return {
      layoutStyle: base.layoutStyle,
      columnCount: base.columnCount,
      columnsTemplate: base.columnsTemplate,
      gridGap: base.gridGap,
      cardWidth: base.cardWidth,
      previewHeight: base.previewHeight,
      identityHeaderHeight: BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT,
      identityPreviewGap: BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP,
      itemHeight: base.previewHeight + BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT +
        BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP,
      horizontalContentInset: base.horizontalContentInset
    };
  }

  resolveTopPadding(topSafeInsetVp: number): number {
    return Math.max(TAB_OVERVIEW_LAYOUT_TOP_PADDING, topSafeInsetVp + TAB_OVERVIEW_LAYOUT_TOP_SAFE_GAP);
  }

  /**
   * Fits one shared snapshot inside the strip's card box without changing its aspect ratio.
   *
   * The strip sizes each card to its own page, so a card whose page is taller than the box would
   * otherwise be cropped to the box's square.
   */
  resolveHorizontalCardFrame(
    input: BrowserTabsOverviewHorizontalCardFrameInput
  ): BrowserTabsOverviewHorizontalCardFrame {
    const maxWidth = Math.max(1, input.maxWidth);
    const maxHeight = Math.max(1, input.maxHeight);
    const snapshotWidth = Math.max(1, input.snapshotWidth);
    const snapshotHeight = Math.max(1, input.snapshotHeight);
    const scale = Math.min(maxWidth / snapshotWidth, maxHeight / snapshotHeight);
    return {
      width: Math.max(1, snapshotWidth * scale),
      height: Math.max(1, snapshotHeight * scale)
    };
  }

  private resolveColumnCount(facts: AppWindowResponsiveFacts): number {
    if (facts.orientation === 'landscape' &&
      this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'md')) {
      return 3;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'lg')) {
      return 4;
    }
    return 2;
  }

  private resolveUsableWidth(input: BrowserTabsOverviewLayoutInput): number {
    if (input.gridWidth > 0) {
      return input.gridWidth;
    }
    return Math.max(1, input.sheetWidth - 32);
  }

  private resolveCardWidth(usableWidth: number, columnCount: number): number {
    const safeColumnCount = Math.max(1, columnCount);
    const totalGap = TAB_OVERVIEW_LAYOUT_GRID_GAP * Math.max(0, safeColumnCount - 1);
    return Math.max(TAB_OVERVIEW_LAYOUT_MIN_CARD_WIDTH, (Math.max(1, usableWidth) - totalGap) / safeColumnCount);
  }

  private resolvePreviewHeight(input: BrowserTabsOverviewLayoutInput, cardWidth: number): number {
    const width = Math.max(0, input.sheetWidth);
    const height = Math.max(0, input.sheetHeight);
    const ratio = this.resolvePreviewRatio(width, height) * TAB_OVERVIEW_LAYOUT_PREVIEW_HEIGHT_MULTIPLIER;
    const maxHeight = this.resolvePreviewMaxHeight(width, height);
    return Math.round(Math.max(
      TAB_OVERVIEW_LAYOUT_MIN_PREVIEW_HEIGHT,
      Math.min(maxHeight, cardWidth * ratio)
    ));
  }

  private resolvePreviewRatio(width: number, height: number): number {
    const facts = this.responsiveLayoutService.resolve({
      viewportWidth: width,
      viewportHeight: height
    });
    if (facts.orientation === 'landscape' &&
      this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'lg')) {
      return TAB_OVERVIEW_LAYOUT_TABLET_LANDSCAPE_PREVIEW_RATIO;
    }
    if (facts.orientation === 'landscape' &&
      this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'md')) {
      return TAB_OVERVIEW_LAYOUT_PHONE_LANDSCAPE_PREVIEW_RATIO;
    }
    return TAB_OVERVIEW_LAYOUT_PORTRAIT_PREVIEW_RATIO;
  }

  private resolvePreviewMaxHeight(width: number, height: number): number {
    if (width > height && height > 0) {
      return Math.max(TAB_OVERVIEW_LAYOUT_MIN_PREVIEW_HEIGHT, height * 0.42);
    }
    return TAB_OVERVIEW_LAYOUT_MAX_PORTRAIT_PREVIEW_HEIGHT;
  }

  private resolveHorizontalCardWidth(input: BrowserTabsOverviewLayoutInput, usableWidth: number): number {
    const landscape = input.sheetWidth > input.sheetHeight;
    const ratio = landscape ?
      TAB_OVERVIEW_HORIZONTAL_CARDS_LANDSCAPE_WIDTH_RATIO :
      TAB_OVERVIEW_HORIZONTAL_CARDS_PHONE_WIDTH_RATIO;
    return Math.round(Math.max(
      TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_WIDTH,
      Math.min(TAB_OVERVIEW_HORIZONTAL_CARDS_MAX_WIDTH, Math.max(1, usableWidth) * ratio)
    ));
  }

  private resolveHorizontalPreviewHeight(input: BrowserTabsOverviewLayoutInput): number {
    return Math.round(Math.max(
      TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_HEIGHT,
      Math.max(1, input.sheetHeight) * TAB_OVERVIEW_HORIZONTAL_CARDS_VIEWPORT_HEIGHT_RATIO
    ));
  }

  private resolveStackCardWidth(input: BrowserTabsOverviewLayoutInput, usableWidth: number): number {
    const landscape = input.sheetWidth > input.sheetHeight;
    const ratio = landscape ?
      TAB_OVERVIEW_STACK_LANDSCAPE_WIDTH_RATIO :
      TAB_OVERVIEW_STACK_PHONE_WIDTH_RATIO;
    return Math.round(Math.max(
      TAB_OVERVIEW_STACK_MIN_WIDTH,
      Math.min(TAB_OVERVIEW_STACK_MAX_WIDTH, Math.max(1, usableWidth) * ratio)
    ));
  }

  private resolveStackPreviewHeight(input: BrowserTabsOverviewLayoutInput): number {
    return Math.round(Math.max(
      TAB_OVERVIEW_STACK_MIN_HEIGHT,
      Math.max(1, input.sheetHeight) * TAB_OVERVIEW_STACK_VIEWPORT_HEIGHT_RATIO
    ));
  }

  private normalizeLayoutStyle(
    style: BrowserTabsOverviewLayoutStyle | string | undefined
  ): BrowserTabsOverviewLayoutStyle {
    // Each of the three styles is its own value; anything else is the default, 卡片平铺.
    return style === 'horizontal_cards' || style === 'stack' ? style : 'grid';
  }

  private buildColumnsTemplate(columnCount: number): string {
    const columns: string[] = [];
    for (let index = 0; index < Math.max(1, columnCount); index += 1) {
      columns.push('1fr');
    }
    return columns.join(' ');
  }

  private resolveResponsiveFacts(input: BrowserTabsOverviewLayoutInput): AppWindowResponsiveFacts {
    return this.responsiveLayoutService.resolve({
      viewportWidth: input.sheetWidth,
      viewportHeight: input.sheetHeight
    });
  }
}
