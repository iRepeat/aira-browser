import {
  BrowserResolvedThemeMode,
  BrowserThemePaletteId
} from '../../common/models/BrowserModels';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';

export interface WebAppearancePolicy {
  darkMode: WebDarkMode;
  forceDarkAccess: boolean;
  backgroundColor: string;
  prefersDarkColorScheme: boolean;
}

/**
 * `WebDarkMode.Auto` is what "do not invert the page, but keep telling it what the
 * system colour scheme is" means, and it is the only correct default for content
 * Aira does not own.
 *
 * `WebDarkMode.Off` is not a neutral value: it disables web dark mode for that Web
 * node, which overrides the system setting and makes the document report
 * `prefers-color-scheme: light` even while the device is in dark mode. A homepage
 * whose dark theme lives behind that media query (as imported third-party homepages
 * commonly do) then paints its light theme first and only flips once its own script
 * runs — the dark-mode cold-start flash. `Auto` follows the system instead, so the
 * media query is already correct on the very first frame.
 */
const DEFAULT_WEB_APPEARANCE_POLICY: WebAppearancePolicy = {
  darkMode: WebDarkMode.Auto,
  forceDarkAccess: true,
  backgroundColor: '#FFFFFF',
  prefersDarkColorScheme: false
};

export interface WebAppearancePolicyThemeRequest {
  paletteId: BrowserThemePaletteId;
  resolvedThemeMode: BrowserResolvedThemeMode;
  forceDarkWebContentEnabled?: boolean;
}

export function resolveWebAppearancePolicy(
  policy?: WebAppearancePolicy
): WebAppearancePolicy {
  if (policy === undefined) {
    return DEFAULT_WEB_APPEARANCE_POLICY;
  }
  return {
    darkMode: policy.darkMode,
    forceDarkAccess: policy.forceDarkAccess === true,
    backgroundColor: policy.backgroundColor,
    prefersDarkColorScheme: policy.prefersDarkColorScheme === true
  };
}

export function resolveWebAppearancePolicyForTheme(
  request: WebAppearancePolicyThemeRequest,
  paletteService: BrowserThemePaletteService = new BrowserThemePaletteService()
): WebAppearancePolicy {
  const tokens = paletteService.resolveTokens(
    request.paletteId,
    request.resolvedThemeMode
  );
  const shouldForceDarkWeb = request.forceDarkWebContentEnabled !== false && tokens.mode === 'dark';
  return resolveWebAppearancePolicy({
    darkMode: shouldForceDarkWeb ? WebDarkMode.On : WebDarkMode.Off,
    forceDarkAccess: shouldForceDarkWeb,
    backgroundColor: tokens.pageBackground,
    prefersDarkColorScheme: shouldForceDarkWeb
  });
}

export function buildWebAppearanceDocumentStartScript(policy: WebAppearancePolicy): string {
  const resolvedPolicy = resolveWebAppearancePolicy(policy);
  const backgroundLiteral = JSON.stringify(resolvedPolicy.backgroundColor);
  const colorSchemeLiteral = JSON.stringify(resolvedPolicy.prefersDarkColorScheme ? 'dark' : 'light');
  return `
(function airaWebAppearanceBootstrap() {
  var background = ${backgroundLiteral};
  var colorScheme = ${colorSchemeLiteral};
  var styleId = '__airaWebAppearanceBootstrapStyle';
  if (document.documentElement && document.documentElement.style) {
    document.documentElement.style.colorScheme = colorScheme;
  }
  var style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = 'html, body { background-color: ' + background + '; color-scheme: ' + colorScheme + '; }';
})();
`;
}

export function buildWebAppearanceDocumentStartScriptItem(policy: WebAppearancePolicy): ScriptItem {
  return {
    script: buildWebAppearanceDocumentStartScript(policy),
    scriptRules: ['.*']
  };
}

/**
 * Appearance bootstrap for a document loaded from a non-HTTP source.
 *
 * `scriptRules` is not protocol-agnostic: ArkWeb only supports the wildcard for
 * HTTP(S) and `data:` sources. For any other protocol the rule must be an exact URL
 * (or a `scheme://` prefix), and a wildcard there silently matches nothing — the
 * script is then never injected and the document paints with its own default
 * appearance. That is what made an imported `file://` homepage flash its light theme
 * on a dark-mode cold start: the forced `color-scheme`/background bootstrap was never
 * running at all.
 *
 * The exact URL is used because the caller always knows the document it is about to
 * load, which is also the only form that is unambiguous for `file://`.
 */
export function buildWebAppearanceDocumentStartScriptItemForUrl(
  policy: WebAppearancePolicy,
  documentUrl: string
): ScriptItem {
  const rule = resolveDocumentStartScriptRule(documentUrl);
  if (rule.length <= 0) {
    return buildWebAppearanceDocumentStartScriptItem(policy);
  }
  return {
    script: buildWebAppearanceDocumentStartScript(policy),
    scriptRules: [rule]
  };
}

/**
 * Resolves the `scriptRules` entry for a document URL.
 *
 * ArkWeb does not accept a `.*` wildcard outside HTTP(S) and `data:`, and for a
 * custom protocol it requires the rule to be the `scheme://` form (Huawei documents
 * `resource://` as the example). A full `file:///...` path is rejected too, which is
 * why an exact-URL rule still injected nothing. Returning the bare scheme prefix is
 * therefore the only form that both parses and matches the imported home document.
 *
 * HTTP(S) and `data:` keep the wildcard: it already matched correctly there, and
 * narrowing it would silently drop injection on parent/child frames.
 */
export function resolveDocumentStartScriptRule(documentUrl: string): string {
  const normalizedUrl = documentUrl.trim();
  if (normalizedUrl.length <= 0) {
    return '';
  }
  const separatorIndex = normalizedUrl.indexOf('://');
  if (separatorIndex <= 0) {
    return '';
  }
  const scheme = normalizedUrl.substring(0, separatorIndex).toLowerCase();
  if (scheme === 'http' || scheme === 'https' || scheme === 'data' || scheme === 'about') {
    return '.*';
  }
  return `${scheme}://`;
}
