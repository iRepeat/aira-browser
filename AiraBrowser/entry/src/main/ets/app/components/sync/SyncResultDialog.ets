import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

type SyncResultDialogRowKind = 'status' | 'paragraph';

interface SyncResultDialogRow {
  key: string;
  kind: SyncResultDialogRowKind;
  label: string;
  value: string;
}

// Status rows read as `名称 —— 状态` on one line, so the name may never grow into the
// status. The dialog shows no sub-lines: everything a row needs must fit that pair.
const SYNC_RESULT_DIALOG_ROW_VERTICAL_PADDING: number = 12;

@CustomDialog
export struct SyncResultDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  controller?: CustomDialogController;
  @Link title: string;
  @Link message: string;

  build() {
    Column({ space: 0 }) {
      Text(this.title.length > 0 ? this.title : '操作结果')
        .width('100%')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 18 })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.buildRows(this.message), (row: SyncResultDialogRow) => {
            if (row.kind === 'status') {
              this.buildStatusRow(row)
            } else {
              this.buildParagraphRow(row)
            }
          }, (row: SyncResultDialogRow) => row.key)
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 340 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      BrowserSheetActionButton({
        stacked: true,
        label: '知道了',
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        fillAvailableWidth: false,
        buttonWidth: '100%',
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.controller?.close();
        }
      })
      .margin({ top: 20 })
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  /**
   * `名称          状态`, separated by a hairline between entries. The name yields first,
   * so the short status stays fully readable.
   */
  @Builder
  private buildStatusRow(row: SyncResultDialogRow) {
    Row({ space: 12 }) {
      Text(row.label)
        .layoutWeight(1)
        .fontSize(14.5)
        .fontWeight(FontWeight.Medium)
        .lineHeight(20)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(row.value)
        .flexShrink(0)
        .fontSize(14.5)
        .fontWeight(FontWeight.Bold)
        .lineHeight(20)
        .fontColor(this.storedAccentColor)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: SYNC_RESULT_DIALOG_ROW_VERTICAL_PADDING, bottom: SYNC_RESULT_DIALOG_ROW_VERTICAL_PADDING })

    this.buildDivider()
  }

  /** A whole-line message still shows as its own entry, aligned left. */
  @Builder
  private buildParagraphRow(row: SyncResultDialogRow) {
    Text(row.value)
      .width('100%')
      .fontSize(14)
      .lineHeight(21)
      .fontColor(this.storedPrimaryTextColor)
      .textAlign(TextAlign.Start)
      .maxLines(5)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({
        top: SYNC_RESULT_DIALOG_ROW_VERTICAL_PADDING,
        bottom: SYNC_RESULT_DIALOG_ROW_VERTICAL_PADDING
      })

    this.buildDivider()
  }

  @Builder
  private buildDivider() {
    Divider()
      .width('100%')
      .height(1)
      .color(this.storedDividerColor)
  }

  /**
   * Turns the coordinator's line-oriented message text into rows.
   *
   * Two shapes are produced upstream:
   * - `名称：状态`, which becomes one status row.
   * - A plain sentence, which stays a full-width paragraph.
   *
   * A row has no sub-line, so a producer must fold any extra sentence into its own
   * `名称：状态` row instead of appending it under another one.
   *
   * The last entry carries no divider, so the list ends on the surface, not on a line.
   */
  private buildRows(message: string): SyncResultDialogRow[] {
    const rows: SyncResultDialogRow[] = [];
    const normalized = message.trim().length > 0 ? message.replace(/\r/g, '') : '操作已完成。';
    const lines = normalized.split('\n').map((line: string) => line.trim()).filter((line: string) => {
      return line.length > 0 && !this.shouldHideTechnicalLine(line);
    });
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const separatorIndex = this.findSeparatorIndex(line);
      if (separatorIndex > 0) {
        const label = line.substring(0, separatorIndex).trim();
        const value = line.substring(separatorIndex + 1).trim();
        if (label.length > 0 && value.length > 0) {
          rows.push({
            key: `${rows.length}-status-${label}`,
            kind: 'status',
            label: label,
            value: value
          });
          continue;
        }
      }
      rows.push({
        key: `${rows.length}-paragraph-${line}`,
        kind: 'paragraph',
        label: '',
        value: line
      });
    }
    if (rows.length === 0) {
      rows.push({
        key: 'fallback',
        kind: 'paragraph',
        label: '',
        value: '操作已完成。'
      });
    }
    return rows;
  }

  private findSeparatorIndex(text: string): number {
    const chineseIndex = text.indexOf('：');
    const asciiIndex = text.indexOf(':');
    if (chineseIndex < 0) {
      return asciiIndex;
    }
    if (asciiIndex < 0) {
      return chineseIndex;
    }
    return Math.min(chineseIndex, asciiIndex);
  }

  private shouldHideTechnicalLine(line: string): boolean {
    const normalized = line.trim().toLowerCase();
    if (normalized.length === 0) {
      return true;
    }
    if (normalized.startsWith('commit：') || normalized.startsWith('commit:') ||
      normalized.indexOf(' commit=') >= 0 || normalized.startsWith('当前 uid：') ||
      normalized.startsWith('当前 uid:') || normalized.startsWith('uid：') ||
      normalized.startsWith('uid:') || normalized.startsWith('技术信息：') ||
      normalized.startsWith('技术信息:')) {
      return true;
    }
    return normalized.startsWith('ok ') || normalized.startsWith('fail ');
  }
}
