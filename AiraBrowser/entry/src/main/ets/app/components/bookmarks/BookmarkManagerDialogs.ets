import { image } from '@kit.ImageKit';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { BookmarkFolderOptionView } from '../../../core/browser/BookmarkFolderSelectionViewModel';
import { BookmarkFolderIcon } from './BookmarkFolderIcon';
import { SiteIconView } from '../common/SiteIconView';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { hasAppResourceText, resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { resolveBookmarkNodeDisplayTitle } from '../../../core/resources/HistoryBookmarkDisplayText';

const BOOKMARK_EDIT_ICON_TARGET_ID: string = 'bookmark-edit-node-dialog';

@CustomDialog
export struct BookmarkManagerCreateFolderDialog {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link folderTitle: string;
  /** Shared by "new folder" and "rename" flows; callers override the copy. */
  @Prop dialogTitle: ResourceStr = $r('app.string.bookmark_new_folder');
  @Prop fieldPlaceholder: ResourceStr = $r('app.string.bookmark_folder_name');
  confirm: (title: string) => void = (_title: string) => {};

  build() {
    Column({ space: 16 }) {
      Text(this.dialogTitle)
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.folderTitle, placeholder: this.fieldPlaceholder })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.folderTitle = value;
        })

      Column({ space: 8 }) {
        BrowserSheetActionButton({
          label: $r('app.string.ui_ok'),
          emphasis: 'primary',
          stacked: true,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm(this.folderTitle);
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: $r('app.string.settings_account_cancel'),
          emphasis: 'ghost',
          stacked: true,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}

@CustomDialog
export struct BookmarkManagerEditNodeDialog {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link nodeTitle: string;
  @Link nodeUrl: string;
  @Link nodeType: string;
  @Link iconPath: string;
  /** Callers that add instead of edit override the heading; empty keeps the edit wording. */
  @Prop dialogTitleOverride: ResourceStr = '';
  /** Move targets for the edited bookmark; empty keeps the picker row hidden for non-bar callers. */
  @Prop folderOptions: BookmarkFolderOptionView[] = [];
  @Prop initialFolderId: string = '';
  confirm: () => void = () => {};
  onFolderChange: (folderId: string) => void = (_folderId: string) => {};
  @State private iconStates: SiteIconListRenderState[] = [];
  @State private currentFolderId: string = '';
  private iconTargetUrl: string = '';
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();

  aboutToAppear(): void {
    this.iconStates = [];
    this.iconTargetUrl = this.nodeUrl.trim();
    this.currentFolderId = this.initialFolderId;
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedIcon(result)
    );
    this.resolveIcon();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    Column({ space: 16 }) {
      this.buildIcon()

      Text(this.resolveDialogTitle())
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.nodeTitle, placeholder: $r('app.string.ui_name') })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.nodeTitle = value;
        })

      if (this.nodeType === 'bookmark') {
        TextInput({ text: this.nodeUrl, placeholder: $r('app.string.ui_url') })
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(this.storedPrimaryTextColor)
          .placeholderColor(this.storedSecondaryTextColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .border({ width: { bottom: 1 }, color: this.storedDividerColor })
          .borderRadius(0)
          .padding({ left: 0, right: 0 })
          .onChange((value: string) => {
            this.nodeUrl = value;
          })
      }

      if (this.nodeType === 'bookmark' && this.folderOptions.length > 0) {
        this.buildFolderPicker()
      }

      Column({ space: 8 }) {
        BrowserSheetActionButton({
          label: $r('app.string.ui_save'),
          emphasis: 'primary',
          stacked: true,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: $r('app.string.settings_account_cancel'),
          emphasis: 'ghost',
          stacked: true,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildFolderPicker() {
    Row({ space: 8 }) {
      Text($r('app.string.bookmark_edit_folder_field'))
        .fontSize(15)
        .fontColor(this.storedSecondaryTextColor)

      Blank()

      Text(this.resolveSelectedFolderTitle())
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([this.storedSecondaryTextColor])
    }
    .width('100%')
    .height(44)
    .border({ width: { bottom: 1 }, color: this.storedDividerColor })
    .accessibilityText($r('app.string.bookmark_edit_folder_field'))
    .bindMenu(this.buildFolderMenu())
  }

  @Builder
  private buildFolderMenu() {
    Menu() {
      ForEach(this.folderOptions, (folder: BookmarkFolderOptionView) => {
        MenuItem({ content: this.buildFolderMenuLabel(folder) })
          .onClick(() => {
            this.selectFolder(folder.id);
          })
      }, (folder: BookmarkFolderOptionView) => folder.id)
    }
    .width(256)
  }

  private selectFolder(folderId: string): void {
    this.currentFolderId = folderId;
    this.onFolderChange(folderId);
  }

  private resolveSelectedFolderTitle(): string {
    const folder = this.folderOptions.find(
      (candidate: BookmarkFolderOptionView): boolean => candidate.id === this.currentFolderId
    );
    if (folder === undefined) {
      return '';
    }
    return resolveAppResourceText(resolveBookmarkNodeDisplayTitle(folder.id, folder.title));
  }

  /** Roots keep their stored Chinese title, and nested folders indent one space per depth. */
  private buildFolderMenuLabel(folder: BookmarkFolderOptionView): string {
    const title = resolveAppResourceText(resolveBookmarkNodeDisplayTitle(folder.id, folder.title));
    const indent = '　'.repeat(folder.depth);
    return indent + title;
  }

  @Builder
  private buildIcon() {
    Row() {
      if (this.nodeType === 'folder') {
        BookmarkFolderIcon({
          widthVp: 42,
          hasContent: false,
          animatePaper: false
        })
      } else if (this.resolveIconUri().length > 0 || this.resolveIconPixelMap() !== undefined) {
        this.buildBookmarkIcon()
      } else {
        SymbolGlyph($r('sys.symbol.bookmark_fill'))
          .fontSize(32)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width(56)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(18)
  }

  @Builder
  private buildBookmarkIcon() {
    SiteIconView({
      iconUri: this.resolveIconUri(),
      iconPixelMap: this.resolveIconPixelMap(),
      fallbackLabel: resolveSiteIconFallbackLabel(this.nodeTitle, this.nodeUrl),
      iconSize: 34,
      cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      frameBorderWidth: 0,
      containerBackgroundColor: this.storedControlBackgroundColor,
      preferPixelMap: this.resolveIconPixelMap() !== undefined,
      sourceRevision: this.resolveIconSourceRevision(),
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.resolvePixelMapAfterUriFailure(iconUri, sourceRevision);
      }
    })
  }

  private resolveDialogTitle(): ResourceStr {
    if (hasAppResourceText(this.dialogTitleOverride)) {
      return this.dialogTitleOverride;
    }
    return this.nodeType === 'folder'
      ? $r('app.string.bookmark_edit_folder')
      : $r('app.string.bookmark_edit_bookmark');
  }

  private resolveIcon(): void {
    this.siteIconListPresenter.resolveTargets(
      this.buildIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedIcon(result),
      { resolutionPolicy: 'memoryOnly' }
    );
  }

  private buildIconTargets(): SiteIconListTarget[] {
    if (this.iconTargetUrl.length <= 0) {
      return [];
    }
    return [{
      id: BOOKMARK_EDIT_ICON_TARGET_ID,
      url: this.iconTargetUrl,
      initialIconUri: this.iconPath
    }];
  }

  private applyResolvedIcon(result: SiteIconListResolvedIcon): void {
    const next = this.siteIconListPresenter.applyResolvedIcon(this.iconStates, result);
    if (next !== this.iconStates) {
      this.iconStates = next;
    }
  }

  private resolveIconUri(): string {
    return this.getIconState()?.path ?? this.iconPath.trim();
  }

  private resolveIconPixelMap(): image.PixelMap | undefined {
    return this.getIconState()?.pixelMap;
  }

  private resolveIconSourceRevision(): number {
    return this.getIconState()?.sourceRevision ?? 0;
  }

  private getIconState(): SiteIconListRenderState | undefined {
    return this.iconStates.find((state: SiteIconListRenderState) => state.id === BOOKMARK_EDIT_ICON_TARGET_ID);
  }

  private resolvePixelMapAfterUriFailure(currentUri: string, sourceRevision: number): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      {
        id: BOOKMARK_EDIT_ICON_TARGET_ID,
        url: this.iconTargetUrl
      },
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedIcon(result)
    );
  }
}

