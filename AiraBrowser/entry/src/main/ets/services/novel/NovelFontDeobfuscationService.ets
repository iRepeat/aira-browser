import { webview } from '@kit.ArkWeb';
import buffer from '@ohos.buffer';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

/**
 * Recovers chapter text that a site renders through a per-response substitution
 * font.
 *
 * The runtime is the Brotli + WOFF2 parser generated into
 * resources/rawfile/novel-font-deobfuscation.js. It has to run in the page for
 * two reasons: HarmonyOS offers no Brotli decoder (`@ohos.zlib` covers zip,
 * gzip and deflate only) and Chromium never implemented
 * `DecompressionStream('brotli')`, so the decode must be bundled; and the font
 * is fetched from the page's own origin so the request carries the page's
 * cookies.
 *
 * The mapping is randomised per response, not per site: two fetches of one
 * chapter yield different codepoints and a different font file. A mapping is
 * therefore never shipped back to ArkTS and never reused across documents;
 * deobfuscation happens in the page that owns the font, via the helper this
 * service builds with buildFixupRuntime().
 *
 * The runtime is injected only after the substitution policy reports a match, so
 * sites without this obfuscation never pay for it.
 */

/** Must match AIRA_NOVEL_FONT_VERSION in the generated runtime. */
export const NOVEL_FONT_RUNTIME_VERSION: string = 'aira-novel-font-1';

const NOVEL_FONT_RUNTIME_RAWFILE: string = 'novel-font-deobfuscation.js';

/**
 * Injection chunk size. The bundle is ~160 KB and is pushed as a series of
 * string literals that are joined in the page, so no single bridge call carries
 * the whole source.
 */
const NOVEL_FONT_INJECTION_CHUNK_SIZE: number = 24000;

export class NovelFontDeobfuscationService {
  private runtimeSource?: string;
  private runtimeUnavailable: boolean = false;

  /**
   * Whether the page-side runtime can still help. Once injection has proven
   * impossible (a page CSP without eval, or an unreadable bundle) every later
   * chapter on that page skips the retry instead of paying for it again.
   */
  canRecover(): boolean {
    return !this.runtimeUnavailable;
  }

  /**
   * Installs the runtime into the current page if it is not already there.
   * Returns whether the runtime is usable afterwards.
   */
  async ensureRuntimeInstalled(controller: webview.WebviewController): Promise<boolean> {
    if (this.runtimeUnavailable) {
      return false;
    }
    if (await this.isRuntimeInstalled(controller)) {
      return true;
    }
    const source: string = this.readRuntimeSource();
    if (source.length <= 0) {
      this.runtimeUnavailable = true;
      return false;
    }
    try {
      await controller.runJavaScript('window.__airaNovelFontChunks = [];');
      for (let offset: number = 0; offset < source.length; offset += NOVEL_FONT_INJECTION_CHUNK_SIZE) {
        const chunk: string = source.substring(offset, offset + NOVEL_FONT_INJECTION_CHUNK_SIZE);
        await controller.runJavaScript(`window.__airaNovelFontChunks.push(${JSON.stringify(chunk)});`);
      }
      await controller.runJavaScript(
        `(function(){ var source = window.__airaNovelFontChunks.join(''); window.__airaNovelFontChunks = null;` +
        ` (0, eval)(source); return 'ok'; })();`
      );
    } catch (_error) {
      this.runtimeUnavailable = true;
      return false;
    }
    return await this.isRuntimeInstalled(controller);
  }

  /**
   * JavaScript helper defining `airaNovelFontFixup(paragraphs, doc, callback)`,
   * appended to an extraction script. It deobfuscates only when the runtime is
   * present and the text actually looks substituted, and it always calls back
   * with an array so a failure degrades to the original text.
   */
  buildFixupRuntime(): string {
    return `
function airaNovelFontFixup(paragraphs, doc, callback){
  try {
    var runtime = window.__airaNovelFont;
    if (!runtime || !runtime.isObfuscated ||
      !runtime.isObfuscated(paragraphs.join(''))){
      callback(paragraphs);
      return;
    }
    runtime.resolveForDocument(doc).then(function(result){
      if (!result || !result.ok || !result.map){ callback(paragraphs); return; }
      var fixed = [];
      for (var i = 0; i < paragraphs.length; i++){
        fixed.push(runtime.deobfuscate(paragraphs[i], result.map));
      }
      callback(fixed);
    }).catch(function(){ callback(paragraphs); });
  } catch (error){
    callback(paragraphs);
  }
}`;
  }

  private async isRuntimeInstalled(controller: webview.WebviewController): Promise<boolean> {
    try {
      const raw: string = await controller.runJavaScript(
        `(function(){ try { var runtime = window.__airaNovelFont;` +
        ` return runtime && runtime.version ? String(runtime.version) : ''; } catch (error){ return ''; } })();`
      );
      const probe: string = this.normalizeRawResult(raw);
      return probe === NOVEL_FONT_RUNTIME_VERSION;
    } catch (_error) {
      return false;
    }
  }

  private readRuntimeSource(): string {
    if (this.runtimeSource !== undefined) {
      return this.runtimeSource;
    }
    try {
      const bytes: Uint8Array = AppRuntimeContext.getApplicationContext()
        .resourceManager.getRawFileContentSync(NOVEL_FONT_RUNTIME_RAWFILE);
      this.runtimeSource = buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('utf8');
    } catch (_error) {
      this.runtimeSource = '';
    }
    return this.runtimeSource;
  }

  /** runJavaScript may return a JSON-quoted string; unwrap it before comparing. */
  private normalizeRawResult(raw: string): string {
    const value: string = String(raw ?? '');
    if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"') {
      try {
        const decoded = JSON.parse(value) as string;
        if (typeof decoded === 'string') {
          return decoded;
        }
      } catch (_error) {
      }
    }
    return value;
  }
}
