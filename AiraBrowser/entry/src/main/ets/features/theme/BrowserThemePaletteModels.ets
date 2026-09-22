import { BrowserThemePaletteId } from '../../common/models/BrowserModels';

export interface BrowserThemeTokenSet {
  accent: string;
  onAccent: string;
  onPrimary: string;
  settingsIconForeground: string;
  settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet;
  syncProviderIconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet;
  activityHeatmap: BrowserActivityHeatmapTokenSet;
  pageBackground: string;
  surfaceBackground: string;
  floatingSurface: string;
  controlBackground: string;
  pressedBackground: string;
  divider: string;
  outline: string;
  textPrimary: string;
  textSecondary: string;
}

export interface BrowserSettingsIconBackgroundTokenSet {
  general: string;
  search: string;
  privacySecurity: string;
  siteSettings: string;
  adBlocker: string;
  userScripts: string;
  siteCustomization: string;
  webpageTranslation: string;
  passwords: string;
  downloads: string;
  userAgent: string;
  appearance: string;
  experiments: string;
  sync: string;
  about: string;
  crossDeviceLink: string;
  customHomepage: string;
  toolbar: string;
  privateMode: string;
  webFeatures: string;
  webApps: string;
  advancedSettings: string;
  bookmarks: string;
  history: string;
  homeShortcuts: string;
  activityHeatmap: string;
  novelBookshelf: string;
  syncMethod: string;
  syncPageCrossDevice: string;
  syncPageAdvanced: string;
  backupFrequency: string;
  backupLocation: string;
  addDevice: string;
  siteLocation: string;
  siteMicrophone: string;
  siteClipboard: string;
  siteExternalActions: string;
}

export interface BrowserSyncProviderIconBackgroundTokenSet {
  cloud: string;
  webdav: string;
}

export interface BrowserActivityHeatmapTokenSet {
  empty: string;
  level1: string;
  level2: string;
  level3: string;
  level4: string;
  todayBorder: string;
}

export const DEFAULT_BROWSER_ACTIVITY_HEATMAP_TOKENS: BrowserActivityHeatmapTokenSet = {
  empty: '#EEF4F1',
  level1: '#B9DDC7',
  level2: '#73B995',
  level3: '#338767',
  level4: '#176148',
  todayBorder: '#176148'
};

export const DEFAULT_DARK_BROWSER_ACTIVITY_HEATMAP_TOKENS: BrowserActivityHeatmapTokenSet = {
  empty: '#1D2826',
  level1: '#244A3C',
  level2: '#317254',
  level3: '#49A074',
  level4: '#78D6A3',
  todayBorder: '#78D6A3'
};

export const DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS: BrowserSettingsIconBackgroundTokenSet = {
  general: '#8E8E93',
  search: '#0A84FF',
  privacySecurity: '#4B3CFF',
  siteSettings: '#00C7BE',
  adBlocker: '#FF375F',
  userScripts: '#FF2D55',
  siteCustomization: '#5E5CE6',
  webpageTranslation: '#E68600',
  passwords: '#34C759',
  downloads: '#5AC8FA',
  userAgent: '#00C853',
  appearance: '#D12BFF',
  experiments: '#FF7A00',
  sync: '#007AFF',
  about: '#0A84FF',
  crossDeviceLink: '#FF3B30',
  customHomepage: '#FF9500',
  toolbar: '#00C6E0',
  privateMode: '#9B00FF',
  webFeatures: '#30D158',
  webApps: '#FF453A',
  advancedSettings: '#6E56FF',
  bookmarks: '#007AFF',
  history: '#FF6B22',
  homeShortcuts: '#FF9500',
  activityHeatmap: '#30D158',
  novelBookshelf: '#FF2D55',
  syncMethod: '#007AFF',
  syncPageCrossDevice: '#FF3B30',
  syncPageAdvanced: '#6E56FF',
  backupFrequency: '#64D2FF',
  backupLocation: '#00C6E0',
  addDevice: '#0A84FF',
  siteLocation: '#FF3B30',
  siteMicrophone: '#FF2D55',
  siteClipboard: '#0A84FF',
  siteExternalActions: '#5E5CE6'
};

export const DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS: BrowserSyncProviderIconBackgroundTokenSet = {
  cloud: '#007AFF',
  webdav: '#6E56FF'
};

export interface BrowserThemePalette {
  id: BrowserThemePaletteId;
  title: string;
  subtitle: string;
  previewColor: string;
  light: BrowserThemeTokenSet;
  dark: BrowserThemeTokenSet;
}
