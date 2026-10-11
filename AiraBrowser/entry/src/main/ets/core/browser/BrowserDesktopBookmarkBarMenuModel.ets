import { BookmarkNode, DesktopBookmarkBarVisibility } from '../../common/models/BrowserModels';
import {
  DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES,
  DesktopBookmarkBarVisibilityChoice
} from './DesktopBookmarkBarVisibility';
import { isBookmarkRootNodeId } from '../../data/repositories/BookmarkRepositoryCore';

/**
 * Menu entry ids for the Large-Screen bookmark bar context menus. The ids are the contract between
 * the pure menu model and the ArkUI surface, so the surface only renders groups and dispatches ids.
 */
export type BrowserDesktopBookmarkBarMenuItemId =
  'open_new_tab' |
  'open_new_window' |
  'open_private_window' |
  'rename_node' |
  'cut_node' |
  'copy_node' |
  'paste_node' |
  'delete_node' |
  'add_bookmark' |
  'add_folder' |
  'open_manager' |
  'bar_visibility_always' |
  'bar_visibility_never' |
  'bar_visibility_new_tab_only';

export interface BrowserDesktopBookmarkBarMenuItem {
  id: BrowserDesktopBookmarkBarMenuItemId;
  label: ResourceStr;
  enabled: boolean;
  checked: boolean;
}

export interface BrowserDesktopBookmarkBarMenuInput {
  node: BookmarkNode;
  barVisibility: DesktopBookmarkBarVisibility;
  /** Whether the in-app bookmark clipboard holds a node that can be pasted. */
  hasClipboardContent: boolean;
}

/** The bar's empty area has no node, so its menu only offers bar-wide commands. */
export interface BrowserDesktopBookmarkBarBlankMenuInput {
  barVisibility: DesktopBookmarkBarVisibility;
}

export interface BrowserDesktopBookmarkBarMenuModel {
  groups: BrowserDesktopBookmarkBarMenuItem[][];
}

interface BrowserDesktopBookmarkBarVisibilityEntry {
  id: BrowserDesktopBookmarkBarMenuItemId;
  choice: DesktopBookmarkBarVisibilityChoice;
}

const OPEN_NEW_TAB_LABEL: ResourceStr = $r('app.string.history_open_new_tab');
const OPEN_NEW_WINDOW_LABEL: ResourceStr = $r('app.string.bookmark_bar_open_new_window');
const OPEN_PRIVATE_WINDOW_LABEL: ResourceStr = $r('app.string.bookmark_bar_open_private');
const RENAME_LABEL: ResourceStr = $r('app.string.bookmark_bar_rename');
const EDIT_BOOKMARK_LABEL: ResourceStr = $r('app.string.bookmark_bar_edit_bookmark');
const CUT_LABEL: ResourceStr = $r('app.string.ui_cut');
const COPY_LABEL: ResourceStr = $r('app.string.ui_copy');
const PASTE_LABEL: ResourceStr = $r('app.string.ui_paste');
const DELETE_LABEL: ResourceStr = $r('app.string.settings_delete');
const ADD_BOOKMARK_LABEL: ResourceStr = $r('app.string.bookmark_bar_add_page');
const ADD_FOLDER_LABEL: ResourceStr = $r('app.string.bookmark_bar_add_folder');
const OPEN_MANAGER_LABEL: ResourceStr = $r('app.string.bookmark_bar_open_manager');

function resolveVisibilityMenuItemId(
  visibility: DesktopBookmarkBarVisibility
): BrowserDesktopBookmarkBarMenuItemId {
  if (visibility === 'never') {
    return 'bar_visibility_never';
  }
  return visibility === 'always' ? 'bar_visibility_always' : 'bar_visibility_new_tab_only';
}

/** Menu ids stay this module's contract; the labels are the shared policy wording. */
const VISIBILITY_ENTRIES: BrowserDesktopBookmarkBarVisibilityEntry[] =
  DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES.map(
    (choice: DesktopBookmarkBarVisibilityChoice): BrowserDesktopBookmarkBarVisibilityEntry => {
      return { id: resolveVisibilityMenuItemId(choice.visibility), choice: choice };
    }
  );

/** Maps a visibility menu entry back to the stored policy it selects. */
export function resolveDesktopBookmarkBarVisibilityForMenuItem(
  id: BrowserDesktopBookmarkBarMenuItemId
): DesktopBookmarkBarVisibility | undefined {
  const entry = VISIBILITY_ENTRIES.find(
    (candidate: BrowserDesktopBookmarkBarVisibilityEntry): boolean => candidate.id === id
  );
  return entry?.choice.visibility;
}

/**
 * Builds the bookmark bar context menu. A folder owns its own contents, so "add" targets the
 * folder itself; a bookmark adds next to its siblings inside the parent folder.
 */
export function buildDesktopBookmarkBarMenuModel(
  input: BrowserDesktopBookmarkBarMenuInput
): BrowserDesktopBookmarkBarMenuModel {
  const node = input.node;
  const isFolder = node.type === 'folder';
  const mutable = !isBookmarkRootNodeId(node.id);
  const groups: BrowserDesktopBookmarkBarMenuItem[][] = [];

  if (isFolder) {
    groups.push(buildVisibilityGroup(input.barVisibility));
    groups.push([buildItem('rename_node', RENAME_LABEL, mutable)]);
    groups.push([buildItem('delete_node', DELETE_LABEL, mutable)]);
    groups.push([
      buildItem('add_bookmark', ADD_BOOKMARK_LABEL, true),
      buildItem('add_folder', ADD_FOLDER_LABEL, true)
    ]);
    return { groups: groups };
  }

  groups.push([
    buildItem('open_new_tab', OPEN_NEW_TAB_LABEL, true),
    buildItem('open_new_window', OPEN_NEW_WINDOW_LABEL, true),
    buildItem('open_private_window', OPEN_PRIVATE_WINDOW_LABEL, true)
  ]);
  groups.push([buildItem('rename_node', EDIT_BOOKMARK_LABEL, mutable)]);
  groups.push([
    buildItem('cut_node', CUT_LABEL, mutable),
    buildItem('copy_node', COPY_LABEL, true),
    buildItem('paste_node', PASTE_LABEL, input.hasClipboardContent)
  ]);
  groups.push([buildItem('delete_node', DELETE_LABEL, mutable)]);
  groups.push([
    buildItem('add_bookmark', ADD_BOOKMARK_LABEL, true),
    buildItem('add_folder', ADD_FOLDER_LABEL, true)
  ]);
  groups.push([buildItem('open_manager', OPEN_MANAGER_LABEL, true)]);
  groups.push(buildVisibilityGroup(input.barVisibility));
  return { groups: groups };
}

/**
 * Builds the empty-area menu of the bar. It carries no node, so it only offers bar-wide commands:
 * the show-hide policy, adding into the bar root, and the bookmark manager.
 */
export function buildDesktopBookmarkBarBlankMenuModel(
  input: BrowserDesktopBookmarkBarBlankMenuInput
): BrowserDesktopBookmarkBarMenuModel {
  return {
    groups: [
      buildVisibilityGroup(input.barVisibility),
      [
        buildItem('add_bookmark', ADD_BOOKMARK_LABEL, true),
        buildItem('add_folder', ADD_FOLDER_LABEL, true)
      ],
      [buildItem('open_manager', OPEN_MANAGER_LABEL, true)]
    ]
  };
}

function buildVisibilityGroup(
  barVisibility: DesktopBookmarkBarVisibility
): BrowserDesktopBookmarkBarMenuItem[] {
  return VISIBILITY_ENTRIES.map(
    (entry: BrowserDesktopBookmarkBarVisibilityEntry): BrowserDesktopBookmarkBarMenuItem => {
      return {
        id: entry.id,
        label: visibilityMenuLabel(entry.id),
        enabled: true,
        checked: entry.choice.visibility === barVisibility
      };
    }
  );
}

function visibilityMenuLabel(id: BrowserDesktopBookmarkBarMenuItemId): ResourceStr {
  if (id === 'bar_visibility_never') {
    return $r('app.string.bookmark_bar_visibility_never');
  }
  if (id === 'bar_visibility_always') {
    return $r('app.string.bookmark_bar_visibility_always');
  }
  return $r('app.string.bookmark_bar_visibility_new_tab');
}

function buildItem(
  id: BrowserDesktopBookmarkBarMenuItemId,
  label: ResourceStr,
  enabled: boolean
): BrowserDesktopBookmarkBarMenuItem {
  return {
    id: id,
    label: label,
    enabled: enabled,
    checked: false
  };
}
