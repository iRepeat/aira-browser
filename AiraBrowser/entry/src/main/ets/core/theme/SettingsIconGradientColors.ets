export interface SettingsIconRgbColor {
  red: number;
  green: number;
  blue: number;
}

const SETTINGS_ICON_GRADIENT_HIGHLIGHT_RATIO: number = 0.2;
const SETTINGS_ICON_GRADIENT_SHADE_RATIO: number = 0.14;

export function parseSettingsIconHexColor(value: string): SettingsIconRgbColor | undefined {
  const normalized = value.trim();
  if (normalized.length !== 7 || normalized.charAt(0) !== '#') {
    return undefined;
  }
  const red = parseHexChannel(normalized.substring(1, 3));
  const green = parseHexChannel(normalized.substring(3, 5));
  const blue = parseHexChannel(normalized.substring(5, 7));
  if (red === undefined || green === undefined || blue === undefined) {
    return undefined;
  }
  return {
    red,
    green,
    blue
  };
}

export function buildSettingsIconHighlightColor(color: SettingsIconRgbColor): string {
  return formatSettingsIconHexColor({
    red: mixSettingsIconChannel(color.red, 255, SETTINGS_ICON_GRADIENT_HIGHLIGHT_RATIO),
    green: mixSettingsIconChannel(color.green, 255, SETTINGS_ICON_GRADIENT_HIGHLIGHT_RATIO),
    blue: mixSettingsIconChannel(color.blue, 255, SETTINGS_ICON_GRADIENT_HIGHLIGHT_RATIO)
  });
}

export function buildSettingsIconShadeColor(color: SettingsIconRgbColor): string {
  return formatSettingsIconHexColor({
    red: mixSettingsIconChannel(color.red, 0, SETTINGS_ICON_GRADIENT_SHADE_RATIO),
    green: mixSettingsIconChannel(color.green, 0, SETTINGS_ICON_GRADIENT_SHADE_RATIO),
    blue: mixSettingsIconChannel(color.blue, 0, SETTINGS_ICON_GRADIENT_SHADE_RATIO)
  });
}

export function formatSettingsIconHexColor(color: SettingsIconRgbColor): string {
  return `#${toHexChannel(color.red)}${toHexChannel(color.green)}${toHexChannel(color.blue)}`;
}

function mixSettingsIconChannel(base: number, tint: number, ratio: number): number {
  return Math.round(base * (1 - ratio) + tint * ratio);
}

function parseHexChannel(value: string): number | undefined {
  const parsed = parseInt(value, 16);
  if (Number.isNaN(parsed) || parsed < 0 || parsed > 255) {
    return undefined;
  }
  const expected = parsed.toString(16).padStart(2, '0');
  if (expected !== value.toLowerCase()) {
    return undefined;
  }
  return parsed;
}

function toHexChannel(value: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(value)));
  return clamped.toString(16).padStart(2, '0').toUpperCase();
}
