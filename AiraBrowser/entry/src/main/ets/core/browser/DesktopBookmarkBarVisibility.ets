import { BrowserAppearanceSettings } from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

export function isDesktopBookmarkBarVisible(settings: BrowserAppearanceSettings): boolean {
  return settings.showDesktopBookmarkBar !== false;
}

export function buildToggledDesktopBookmarkBarSettings(
  current: BrowserAppearanceSettings
): BrowserAppearanceSettings {
  return {
    bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
    globalImmersionEnabled: current.globalImmersionEnabled,
    alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
    forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
    blurPrivateTabPreviews: current.blurPrivateTabPreviews,
    showHomeRecentlyClosed: current.showHomeRecentlyClosed,
    showHomeShortcuts: current.showHomeShortcuts,
    homeRecentlyClosedLimit: current.homeRecentlyClosedLimit,
    homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
    homeShortcutIconSizeRatio: current.homeShortcutIconSizeRatio,
    siteIconCornerRadiusRatio: current.siteIconCornerRadiusRatio,
    themePaletteId: current.themePaletteId,
    tabsOverviewLayoutStyle: current.tabsOverviewLayoutStyle,
    tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
    showDesktopBookmarkBar: !isDesktopBookmarkBarVisible(current)
  };
}

export async function toggleDesktopBookmarkBarVisibility(
  repository: PreferencesRepository
): Promise<boolean> {
  const next = buildToggledDesktopBookmarkBarSettings(repository.getPreferences().appearance);
  await repository.updateAppearanceSettings(next);
  return isDesktopBookmarkBarVisible(next);
}
