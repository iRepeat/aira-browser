import { describe, expect, it } from '@ohos/hypium';
import {
  NOVEL_FONT_MIN_SUBSTITUTED_RATIO,
  NovelFontSubstitutionPolicy
} from '../main/ets/features/novel/NovelFontSubstitutionPolicy';

/** Builds a string of `count` CJK Extension B characters. */
function substitutedRun(count: number): string {
  let text: string = '';
  for (let index: number = 0; index < count; index += 1) {
    text += String.fromCodePoint(0x20000 + index);
  }
  return text;
}

export default function novelFontSubstitutionPolicyTest(): void {
  describe('NovelFontSubstitutionPolicy', () => {
    it('does not flag ordinary Chinese prose', 0, () => {
      const policy = new NovelFontSubstitutionPolicy();

      // Real text from a chapter page, containing no extension-plane characters.
      const prose: string = '粟粟在田里插秧。四月底的天气，太阳已是很晒了，按说这秧苗还能再养两日。';

      expect(policy.isSubstitutedText(prose)).assertFalse();
      expect(policy.isSubstitutedParagraphs([prose, prose])).assertFalse();
      expect(policy.measure(prose).substituted).assertEqual(0);
    });

    it('flags text drawn through a substitution font', 0, () => {
      const policy = new NovelFontSubstitutionPolicy();

      // The real page substitutes roughly 70% of characters; the surrounding
      // punctuation stays intact, so a ratio slightly below 1 is the norm.
      const substituted: string = `${substitutedRun(60)}，${substitutedRun(40)}。`;

      expect(policy.isSubstitutedText(substituted)).assertTrue();
      expect(policy.isSubstitutedParagraphs(['ordinary text', substituted])).assertTrue();
    });

    it('ignores a single archaic character', 0, () => {
      const policy = new NovelFontSubstitutionPolicy();

      // One extension character is plausible in genuine prose and must not, on
      // its own, trigger the recovery path.
      const mostlyPlain: string = `此字${String.fromCodePoint(0x20000)}罕见，其余皆是常文。`;

      expect(policy.isSubstitutedText(mostlyPlain)).assertFalse();
    });

    it('requires the substituted share to clear the ratio threshold', 0, () => {
      const policy = new NovelFontSubstitutionPolicy();

      // Enough substituted characters to pass the count gate, but a long clean
      // body keeps the share below the ratio threshold.
      const sparse: string = substitutedRun(8) + '常'.repeat(400);

      expect(policy.measure(sparse).substituted).assertEqual(8);
      expect(policy.measure(sparse).ratio < NOVEL_FONT_MIN_SUBSTITUTED_RATIO).assertTrue();
      expect(policy.isSubstitutedText(sparse)).assertFalse();
    });

    it('counts astral characters once and skips whitespace', 0, () => {
      const policy = new NovelFontSubstitutionPolicy();

      const measurement = policy.measure(` ${substitutedRun(10)} \n\t `);

      // Ten substituted characters, no plain ones, whitespace excluded entirely.
      expect(measurement.total).assertEqual(10);
      expect(measurement.substituted).assertEqual(10);
      expect(measurement.ratio).assertEqual(1);
    });

    it('handles empty and whitespace-only text', 0, () => {
      const policy = new NovelFontSubstitutionPolicy();

      expect(policy.measure('').total).assertEqual(0);
      expect(policy.measure('').ratio).assertEqual(0);
      expect(policy.isSubstitutedText('')).assertFalse();
      expect(policy.isSubstitutedText('   \n  ')).assertFalse();
      expect(policy.isSubstitutedParagraphs([])).assertFalse();
    });
  });
}
