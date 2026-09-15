/**
 * Detects Novel pages whose chapter text is drawn with a substitution font, and
 * applies a recovered codepoint mapping.
 *
 * Some Chinese novel sites defeat text extraction by replacing every content
 * character with a rare codepoint and rendering the real glyph from a private
 * font. The served bytes are valid UTF-8, so this is not an encoding fault: the
 * text is only readable through the font. The page's own font is therefore the
 * only source of truth, and reading it is what NovelFontDeobfuscationService
 * does; this policy is the pure half that decides whether recovery is needed
 * at all and performs the final substitution.
 *
 * The thresholds mirror the page-side runtime. A page pays for the recovery
 * runtime only after this policy reports substitution, so ordinary pages keep
 * their existing path untouched.
 */

/** Plane start of CJK Extension B, where the substitution fonts draw from. */
const SUBSTITUTION_PLANE_START: number = 0x20000;

/**
 * Minimum substituted characters before a page is treated as obfuscated. A
 * single archaic character is plausible in real prose; a run of them is not.
 */
export const NOVEL_FONT_MIN_SUBSTITUTED_COUNT: number = 8;

/**
 * Minimum substituted share of non-whitespace characters. Kept below 1.0
 * because the fonts leave punctuation and digits intact.
 */
export const NOVEL_FONT_MIN_SUBSTITUTED_RATIO: number = 0.05;

export interface NovelFontSubstitutionMeasurement {
  total: number;
  substituted: number;
  ratio: number;
}

export class NovelFontSubstitutionPolicy {
  /**
   * Counts substituted characters and their share of the non-whitespace text.
   * Iterates by code point so an astral character counts once, not twice.
   */
  measure(text: string): NovelFontSubstitutionMeasurement {
    let total: number = 0;
    let substituted: number = 0;
    let index: number = 0;
    while (index < text.length) {
      const code: number = this.codePointAt(text, index);
      index += this.codeUnitSize(code);
      if (this.isWhitespaceCode(code)) {
        continue;
      }
      total += 1;
      if (code >= SUBSTITUTION_PLANE_START) {
        substituted += 1;
      }
    }
    return {
      total: total,
      substituted: substituted,
      ratio: total > 0 ? substituted / total : 0
    };
  }

  /** Whether the paragraphs look drawn with a substitution font. */
  isSubstitutedText(text: string): boolean {
    const measurement: NovelFontSubstitutionMeasurement = this.measure(text);
    if (measurement.substituted < NOVEL_FONT_MIN_SUBSTITUTED_COUNT) {
      return false;
    }
    return measurement.ratio >= NOVEL_FONT_MIN_SUBSTITUTED_RATIO;
  }

  /** Whether any paragraph looks drawn with a substitution font. */
  isSubstitutedParagraphs(paragraphs: string[]): boolean {
    return paragraphs.some((paragraph: string): boolean => this.isSubstitutedText(paragraph));
  }

  private codePointAt(text: string, index: number): number {
    const code: number | undefined = text.codePointAt(index);
    return code === undefined ? text.charCodeAt(index) : code;
  }

  private codeUnitSize(code: number): number {
    return code > 0xFFFF ? 2 : 1;
  }

  private isWhitespaceCode(code: number): boolean {
    return code === 0x20 || code === 0x09 || code === 0x0A || code === 0x0D ||
      code === 0x00A0 || code === 0x3000;
  }
}
