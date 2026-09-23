import { resolveDownloadFileType } from '../../../core/download/DownloadFileTypeResolver';
import { PendingDownloadPromptState } from '../../../services/download/DownloadRuntimeService';
import { resolveDownloadFileTypeImage } from './DownloadFileTypeIcon';
import { BrowserDownloadConfirmOverlayAction } from '../../../core/browser/BrowserDownloadConfirmOverlayCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from './BrowserModalBottomSheet';
import {
  resolveCenteredDialogSurfaceColor,
  CENTERED_DIALOG_CORNER_RADIUS_VP,
  CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER
} from '../common/CenteredDialogSurface';

const DOWNLOAD_FILE_NAME_MAX_LENGTH: number = 180;
const DOWNLOAD_CONFIRM_FILE_ICON_SIZE: number = 64;
const DOWNLOAD_CONFIRM_ROW_HEIGHT: number = 46;

@CustomDialog
struct BrowserDownloadConfirmDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link @Watch('resetEditingForPrompt') prompt: PendingDownloadPromptState | undefined;
  @Link fileNameDraft: string;
  @State private editingFileName: boolean = false;
  onAction: (action: BrowserDownloadConfirmOverlayAction) => void =
    (_action: BrowserDownloadConfirmOverlayAction): void => {};
  private boundPromptGuid: string = '';

  aboutToAppear(): void {
    this.resetEditingForPrompt();
  }

  build() {
    Column() {
      if (this.prompt !== undefined) {
        this.buildContent(this.prompt!)
      }
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * Centered file mark, then one list: name, size, source, save location.
   * The name stays a value until tapped, so a long name can keep its extension
   * instead of being clipped by a single-line field.
   */
  @Builder
  private buildContent(prompt: PendingDownloadPromptState) {
    this.buildFileIcon()

    Column() {
      this.buildFileNameRow()
      if (prompt.totalBytes > 0) {
        this.buildValueRow('大小', this.formatBytes(prompt.totalBytes), EllipsisMode.END)
      }
      this.buildValueRow('来源', this.resolveSourceText(prompt), EllipsisMode.CENTER)
      this.buildLocationRow(prompt)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)

    Column({ space: 10 }) {
      BrowserSheetActionButton({
        stacked: true,
        label: prompt.confirmLabel,
        emphasis: 'primary',
        actionEnabled: this.fileNameDraft.trim().length > 0,
        accentColor: this.storedAccentColor,
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.onAction({
            type: 'confirm',
            guid: prompt.guid,
            fileName: this.fileNameDraft
          });
        }
      })

      BrowserSheetActionButton({
        stacked: true,
        label: prompt.cancelLabel,
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.onAction({ type: 'cancel', guid: prompt.guid });
        }
      })
    }
    .width('100%')
    .margin({ top: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildFileIcon() {
    Image(this.resolveFileTypeImage())
      .width(DOWNLOAD_CONFIRM_FILE_ICON_SIZE)
      .height(DOWNLOAD_CONFIRM_FILE_ICON_SIZE)
      .margin({ bottom: 18 })
      .objectFit(ImageFit.Contain)
      .accessibilityText(this.resolveFileNameDisplay())
  }

  @Builder
  private buildFileNameRow() {
    Row({ space: 12 }) {
      this.buildRowLabel('文件名')

      if (this.editingFileName) {
        TextInput({ text: this.fileNameDraft, placeholder: '文件名' })
          .layoutWeight(1)
          .height(32)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .placeholderColor(this.storedSecondaryTextColor)
          .caretColor(this.storedAccentColor)
          .textAlign(TextAlign.End)
          .style(TextInputStyle.Inline)
          .backgroundColor(this.storedControlBackgroundColor)
          .border({ width: 1, color: this.storedAccentColor })
          .borderRadius(8)
          .padding({ left: 8, right: 8 })
          .maxLength(DOWNLOAD_FILE_NAME_MAX_LENGTH)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .onChange((value: string) => {
            this.fileNameDraft = value;
          })
          .onBlur(() => {
            this.finishFileNameEdit();
          })
          .onSubmit(() => {
            this.finishFileNameEdit();
          })
      } else {
        Text(this.resolveFileNameDisplay())
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveFileNameColor())
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.CENTER)
      }
    }
    .width('100%')
    .height(DOWNLOAD_CONFIRM_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.editingFileName) {
        this.editingFileName = true;
      }
    })
  }

  @Builder
  private buildValueRow(label: string, value: string, ellipsisMode: EllipsisMode) {
    Row({ space: 12 }) {
      this.buildRowLabel(label)
      Text(value)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .ellipsisMode(ellipsisMode)
    }
    .width('100%')
    .height(DOWNLOAD_CONFIRM_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: 1 }, color: this.storedDividerColor })
  }

  @Builder
  private buildRowLabel(label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.storedSecondaryTextColor)
      .maxLines(1)
      .flexShrink(0)
  }

  @Builder
  private buildLocationRow(prompt: PendingDownloadPromptState) {
    Row({ space: 12 }) {
      this.buildRowLabel('保存到')

      Text(prompt.locationPath)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .ellipsisMode(EllipsisMode.START)

      if (prompt.canChangeLocation) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width('100%')
    .height(DOWNLOAD_CONFIRM_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: 1 }, color: this.storedDividerColor })
    .enabled(prompt.canChangeLocation)
    .onClick(() => {
      if (prompt.canChangeLocation) {
        this.onAction({ type: 'change_location', guid: prompt.guid });
      }
    })
  }

  private resetEditingForPrompt(): void {
    const guid = this.prompt === undefined ? '' : this.prompt.guid;
    if (guid === this.boundPromptGuid) {
      return;
    }
    this.boundPromptGuid = guid;
    this.editingFileName = false;
  }

  private finishFileNameEdit(): void {
    if (!this.editingFileName) {
      return;
    }
    this.editingFileName = false;
  }

  private resolveFileNameDisplay(): string {
    const draft = this.fileNameDraft.trim();
    return draft.length > 0 ? this.fileNameDraft : '文件名';
  }

  private resolveFileNameColor(): ResourceColor {
    return this.fileNameDraft.trim().length > 0 ? this.storedPrimaryTextColor : this.storedSecondaryTextColor;
  }

  private resolveFileTypeImage(): Resource {
    return resolveDownloadFileTypeImage(resolveDownloadFileType(
      this.fileNameDraft,
      this.prompt?.mimeType
    ));
  }

  private resolveSourceText(prompt: PendingDownloadPromptState): string {
    const sourceHost = prompt.sourceHost.trim();
    if (sourceHost.length > 0) {
      return sourceHost;
    }
    const sourceUrl = prompt.url.trim();
    return sourceUrl.length > 0 ? sourceUrl : '未知来源';
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(bytes < 1024 * 100 ? 1 : 0)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(bytes < 1024 * 1024 * 100 ? 1 : 0)} MB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  }
}

@Component
export struct BrowserDownloadConfirmOverlay {
  @Prop @Watch('syncVisibility') visible: boolean = false;
  @Prop @Watch('syncPrompt') prompt: PendingDownloadPromptState | undefined = undefined;
  @State private currentPrompt: PendingDownloadPromptState | undefined = undefined;
  @State private fileNameDraft: string = '';
  onAction: (action: BrowserDownloadConfirmOverlayAction) => void =
    (_action: BrowserDownloadConfirmOverlayAction): void => {};
  private dialogOpen: boolean = false;
  private decisionCommitted: boolean = false;
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserDownloadConfirmDialog({
      prompt: $currentPrompt,
      fileNameDraft: $fileNameDraft,
      onAction: (action: BrowserDownloadConfirmOverlayAction): void => {
        this.commitAction(action);
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
      this.handleInteractiveDismiss();
      dismissDialogAction.dismiss();
    }
  });

  aboutToAppear(): void {
    this.syncPrompt();
    this.syncVisibility();
  }

  aboutToDisappear(): void {
    this.closeDialog();
  }

  build() {
    Row()
      .width(0)
      .height(0)
      .hitTestBehavior(HitTestMode.None)
  }

  private syncPrompt(): void {
    const nextPrompt = this.prompt;
    if (nextPrompt === undefined) {
      this.currentPrompt = undefined;
      this.fileNameDraft = '';
      this.closeDialog();
      return;
    }
    // Only seed the draft when the prompt identity changes. A location change
    // re-publishes the same prompt, and resetting the draft there would throw
    // away a filename the user had already typed.
    if (this.currentPrompt?.guid !== nextPrompt.guid) {
      this.fileNameDraft = nextPrompt.fileName;
    }
    this.currentPrompt = nextPrompt;
    this.syncVisibility();
  }

  private syncVisibility(): void {
    if (this.visible && this.currentPrompt !== undefined) {
      this.openDialog();
      return;
    }
    this.closeDialog();
  }

  private openDialog(): void {
    if (this.dialogOpen) {
      return;
    }
    this.decisionCommitted = false;
    this.dialogOpen = true;
    this.dialogController.open();
  }

  private commitAction(action: BrowserDownloadConfirmOverlayAction): void {
    // Changing the location is not a decision: the dialog stays open so the user
    // can then confirm or cancel with the new folder in view.
    if (action.type === 'change_location') {
      this.onAction(action);
      return;
    }
    if (this.decisionCommitted) {
      return;
    }
    this.decisionCommitted = true;
    this.onAction(action);
    if (this.visible && this.currentPrompt !== undefined && this.currentPrompt.guid !== action.guid) {
      this.decisionCommitted = false;
      return;
    }
    this.closeDialog();
  }

  private handleInteractiveDismiss(): void {
    if (this.decisionCommitted) {
      return;
    }
    this.decisionCommitted = true;
    this.dialogOpen = false;
    if (this.currentPrompt !== undefined) {
      this.onAction({ type: 'cancel', guid: this.currentPrompt.guid });
      return;
    }
    this.onAction({ type: 'reset' });
  }

  private closeDialog(): void {
    if (!this.dialogOpen) {
      return;
    }
    this.dialogOpen = false;
    try {
      this.dialogController.close();
    } catch (_error) {
    }
  }
}
